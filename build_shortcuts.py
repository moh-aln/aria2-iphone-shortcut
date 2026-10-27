#!/usr/bin/env python3
"""Build the "aria2" shortcut, plus the script that sets everything up on the phone.

Writes into shortcuts/:
  aria2.shortcut      unsigned; to use it directly, sign it on a Mac:
                      shortcuts sign -m anyone -i aria2.shortcut -o "aria2 (signed).shortcut"
  setup-on-phone.sh   run in iSH-AOK: installs aria2, yt-dlp, dl, its pictures, web.py and formats.py, asks for
                      location access, then signs the shortcut with RoutineHub's HubSign
                      service into /root/Shortcuts, and into the Files folder at /mnt/phone
and the pictures for dl's menus into icons/ (drawn by icons.py).

The iSH-AOK identifiers below come from its source (github.com/emkey1/ish-AOK):
app/ISHRunCommandIntent.swift for the intent and its parameters, and
fastlane/Appfile for the bundle ID and team ID of the TestFlight build.
The plist layout follows Cherri's encoders (github.com/electrikmilk/cherri).
"""
import base64
import hashlib
import itertools
import json
import plistlib
import re
import uuid
from pathlib import Path

import icons

HERE = Path(__file__).resolve().parent
OUT = HERE / "shortcuts"
NAME = "aria2"

ISH_AOK = {
    "BundleIdentifier": "app.ish.iSH-AOK",
    "Name": "iSH-AOK",
    "TeamIdentifier": "UYU5FM4LQ4",
}
CLIENT_VERSION = "4033.0.4.3"  # Shortcuts on iOS 26
OBJECT = "￼"  # where a variable sits inside a text field
SHORTCUT_INPUT = {"Type": "ExtensionInput"}

# Icon colour and glyph, as numbered by the Shortcuts app.
TEAL, DOWNLOAD_GLYPH = 431817727, 59693
# What this shortcut can do, which dl reads from its version ("<level>-<hash>"). Raise it
# whenever the shortcut learns an answer from dl that older ones don't know (see dl -ui).
# Level 3: @@web:, @@copy: and @@share:. (c1a2b4d4 was level 2; it had no level in its version.)
# Level 4: @@notify:; it sends what's shared as @@add: and the clipboard as @@paste:, and
# gives dl -ui 120 s.
# Level 5: @@again:<key>, which runs dl -ui again at once with the answer as it is: a long
# wait is many short Run Commands, since iOS stops a long one with "an unknown error".
LEVEL = 5
# If conditions, as numbered by the Shortcuts app.
BEGINS_WITH, HAS_ANY_VALUE = 8, 100
# Control flow: the opening action of a block, its "Otherwise", and its "End".
START, MIDDLE, END = 0, 1, 2


# UUIDs only link actions to each other, so number them: the same shortcut builds to the same
# file, and its hash says whether the shortcut changed since the user last imported it.
_uuids = itertools.count(1)


def new_uuid():
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"aria2-shortcut/{next(_uuids)}")).upper()


def output_of(action, name):
    return {"Type": "ActionOutput", "OutputUUID": action["WFWorkflowActionParameters"]["UUID"], "OutputName": name}


def attachment(variable):
    return {"WFSerializationType": "WFTextTokenAttachment", "Value": variable}


def text(*parts):
    """A text field: plain strings mixed with variables (dicts made by output_of)."""
    string, attachments = "", {}
    for part in parts:
        if isinstance(part, str):
            string += part
        else:
            # Ranges count UTF-16 code units; everything before a variable here is ASCII.
            attachments[f"{{{len(string)}, 1}}"] = part
            string += OBJECT
    return {"WFSerializationType": "WFTextTokenString",
            "Value": {"string": string, "attachmentsByRange": attachments}}


def action(identifier, **params):
    """A Shortcuts action: a built-in one by its short name ("gettext", "text.split"), or an
    app's App Intent by its full identifier ("app.ish.iSH-AOK.ISHRunCommandIntent")."""
    params.setdefault("UUID", new_uuid())
    if not identifier.startswith("app."):
        identifier = "is.workflow.actions." + identifier
    return {"WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": params}


def control(identifier, group, mode, **params):
    # Like Cherri: only the End of a block carries a UUID.
    params.update(GroupingIdentifier=group, WFControlFlowMode=mode)
    if mode == END:
        params["UUID"] = new_uuid()
    return {"WFWorkflowActionIdentifier": "is.workflow.actions." + identifier,
            "WFWorkflowActionParameters": params}


def if_(group, variable, condition, value=None):
    params = {"WFInput": {"Type": "Variable", "Variable": attachment(variable)}, "WFCondition": condition}
    if value is not None:
        params["WFConditionalActionString"] = value
    return control("conditional", group, START, **params)


def chain(value, branches, otherwise):
    """If value begins with the first branch's prefix, that branch's actions; otherwise the
    next branch's, and so on; and if none, `otherwise`."""
    if not branches:
        return otherwise
    (prefix, then), rest = branches[0], branches[1:]
    group = new_uuid()
    return [if_(group, value, BEGINS_WITH, prefix), *then, control("conditional", group, MIDDLE),
            *chain(value, rest, otherwise), control("conditional", group, END)]


def run_command(*command, timeout=None):
    """iSH-AOK's Run Command. Its timeout is 20 s unless given (at most 120)."""
    params = {"timeout": timeout} if timeout else {}
    return action("app.ish.iSH-AOK.ISHRunCommandIntent",
                  AppIntentDescriptor={**ISH_AOK, "AppIntentIdentifier": "ISHRunCommandIntent"},
                  command=text(*command), **params)


def run_with_base64(command, variable, after="", timeout=None):
    """Run `<command> '<variable, base64-encoded>'<after>`, so nothing in it can act as shell syntax."""
    as_text = action("gettext", WFTextActionText=text(variable))
    encoded = action("base64encode", WFEncodeMode="Encode", WFInput=attachment(output_of(as_text, "Text")))
    run = run_command(f"{command} '", output_of(encoded, "Base64 Encoded"), "'" + after, timeout=timeout)
    return [as_text, encoded, run], run


def open_ish_aok():
    return action("openapp", WFAppIdentifier=ISH_AOK["BundleIdentifier"], WFSelectedApp=ISH_AOK)


def set_variable(name, value):
    return action("setvariable", WFVariableName=name, WFInput=attachment(value))


def variable(name):
    return {"Type": "Variable", "VariableName": name}


def as_contacts(value):
    """The value read as contacts: a .vcf file becomes one contact per vCard (Cherri's `.contact`)."""
    return {**value, "Aggrandizements": [
        {"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": "WFContactContentItem"}]}


def aria2(version):
    """The shortcut. It tells dl its version, so dl knows which answers and screens it takes."""
    acts = []

    # dl's screens (see `dl -ui`), one after another until it's closed. Each time round, dl
    # gets what was tapped last and this shortcut's version, and prints the next screen, or
    # an answer only the Shortcut can carry out. The first time, that's "@@start", or what
    # was shared from another app as "@@add:<it>": dl then either starts it (and answers
    # with a notification, and close) or asks how to download a video. Downloads carry on
    # in the background as long as iSH-AOK may use location Always (see keep_awake in dl).
    start_text = action("gettext", WFTextActionText=text("@@start"))
    acts += [start_text, set_variable("tapped", output_of(start_text, "Text"))]
    shared = new_uuid()
    add_text = action("gettext", WFTextActionText=text("@@add:", SHORTCUT_INPUT))
    acts += [if_(shared, SHORTCUT_INPUT, HAS_ANY_VALUE), add_text, set_variable("tapped", output_of(add_text, "Text")),
             control("conditional", shared, END)]
    loop = new_uuid()
    # 120 s, the most iSH-AOK allows. iOS gives it only about 30 s in the background, though,
    # so dl never waits long in one go (see @@again).
    ui, run = run_with_base64("dl -ui -b", variable("tapped"), f" -k {version}", timeout=120)
    answer = output_of(run, "Run Command")
    acts += [control("repeat.count", loop, START, WFRepeatCount=500), *ui]

    # @@open:<link>: open it (a file or folder in Files, or the App Store), then close.
    opens = new_uuid()
    link = action("text.replace", WFInput=text(answer), WFReplaceTextFind="@@open:", WFReplaceTextReplace="")
    acts += [if_(opens, answer, BEGINS_WITH, "@@open:"), link,
             action("openurl", WFInput=text(output_of(link, "Updated Text"))), action("exit"),
             control("conditional", opens, END)]
    close, open_app = new_uuid(), new_uuid()
    acts += [if_(close, answer, BEGINS_WITH, "@@exit"), action("exit"),
             control("conditional", close, END)]
    acts += [if_(open_app, answer, BEGINS_WITH, "@@app"), open_ish_aok(), action("exit"),
             control("conditional", open_app, END)]

    # @@import: dl prints the new shortcut, signed, as base64. Opened as a .shortcut file, it
    # makes iOS offer to import it, so nobody has to find it in Files.
    imports = new_uuid()
    fetch = run_command("dl --shortcut")
    decoded = action("base64encode", WFEncodeMode="Decode", WFInput=attachment(output_of(fetch, "Run Command")))
    named = action("setitemname", WFInput=attachment(output_of(decoded, "Base64 Decoded")),
                   WFName=f"{NAME}.shortcut")
    acts += [if_(imports, answer, BEGINS_WITH, "@@import"), fetch, decoded, named,
             action("openin", WFInput=attachment(output_of(named, "Renamed Item")), WFOpenInAskWhenRun=False),
             action("exit"), control("conditional", imports, END)]

    # @@clipboard: add the copied link. Anything else is a screen to choose from: vCards,
    # which, saved as a .vcf and read as contacts, show as rows with a picture and a line
    # under the title (the trick Cherri's chooseFromVCard uses), or plain lines.
    def again():  # then dl shows the same screen again
        nothing = action("gettext", WFTextActionText=text(""))
        return [nothing, set_variable("tapped", output_of(nothing, "Text"))]

    def without(prefix):  # the answer after its "@@…:"
        return action("text.replace", WFInput=text(answer), WFReplaceTextFind=prefix, WFReplaceTextReplace="")

    # @@clipboard: dl gets the clipboard as "@@paste:<it>", and asks about a video as it
    # would about a shared one.
    clipboard = action("getclipboard")
    pasted = action("gettext", WFTextActionText=text("@@paste:", output_of(clipboard, "Clipboard")))
    # @@notify:<text>: a notification, then close.
    notice = without("@@notify:")
    # @@web:<link>: the live view or the player, in a Safari sheet. The loop carries on
    # once it's closed.
    page = without("@@web:")
    copied, shared = without("@@copy:"), without("@@share:")
    vcards = action("gettext", WFTextActionText=text(answer))
    menu = action("setitemname", WFInput=attachment(output_of(vcards, "Text")), WFName="menu.vcf")
    pick = action("choosefromlist", WFInput=attachment(as_contacts(output_of(menu, "Renamed Item"))),
                  WFChooseFromListActionPrompt=NAME)
    title = action("properties.contacts", WFInput=attachment(output_of(pick, "Chosen Item")),
                   WFContentItemPropertyName="Name")
    lines = action("text.split", text=text(answer), WFTextSeparator="New Lines")
    choose = action("choosefromlist", WFInput=attachment(output_of(lines, "Split Text")),
                    WFChooseFromListActionPrompt=NAME)
    acts += chain(answer, [
        ("@@clipboard", [clipboard, pasted, set_variable("tapped", output_of(pasted, "Text"))]),
        ("@@notify:", [notice, action("notification", WFNotificationActionTitle=NAME,
                                      WFNotificationActionBody=text(output_of(notice, "Updated Text"))),
                       action("exit")]),
        ("@@web:", [page, action("showwebpage", WFURL=text(output_of(page, "Updated Text"))), *again()]),
        ("@@copy:", [copied, action("setclipboard", WFInput=attachment(output_of(copied, "Updated Text"))), *again()]),
        ("@@share:", [shared, action("share", WFInput=attachment(output_of(shared, "Updated Text"))), *again()]),
        # @@again:<key>: run dl again at once, with the answer as what was tapped.
        ("@@again:", [set_variable("tapped", answer)]),
        ("BEGIN:VCARD", [vcards, menu, pick, title, set_variable("tapped", output_of(title, "Name"))]),
    ], [lines, choose, set_variable("tapped", output_of(choose, "Chosen Item"))])

    acts.append(control("repeat.count", loop, END))
    return {
        "WFWorkflowClientVersion": CLIENT_VERSION,
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": TEAL, "WFWorkflowIconGlyphNumber": DOWNLOAD_GLYPH},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowOutputContentItemClasses": [],
        "WFQuickActionSurfaces": [],
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowActions": acts,
        "WFWorkflowTypes": ["ActionExtension"],
        "WFWorkflowInputContentItemClasses": ["WFURLContentItem", "WFStringContentItem"],
        "WFWorkflowHasShortcutInputVariables": True,
    }


SETUP = """\
#!/bin/sh
# Sets up (or updates) downloads in iSH-AOK: installs aria2, yt-dlp (with Node and QuickJS
# for YouTube, and ffmpeg for joining video and audio), curl, the dl script and the pictures
# for its menus; asks for location access, which keeps downloads going in the background;
# then signs the "aria2" shortcut with RoutineHub's HubSign service (the signer Cherri and
# RoutineHub tools use) and puts it in the Files folder mounted at /mnt/phone.
# dl runs the newest copy of this script from the project's repository when it changes,
# with DL_APP_ONLY=1: then the tools are left alone, since they have their own update.
# Generated by build_shortcuts.py.

mkdir -p /root/Downloads/.logs

# Location updates are what keep iSH-AOK running when it's not on screen, so start them
# first: then the install below carries on if you leave the app. The first time, iOS asks.
# A download may already be keeping them going; then leave that alone.
echo "iSH-AOK will ask for location access: allow it. It keeps this setup going if you leave"
echo "the app, and later keeps downloads going in the background."
awake=
if ! pgrep -f 'dd if[= ]/dev/location' >/dev/null; then  # BusyBox dd rewrites its arguments
  nohup dd if=/dev/location of=/dev/null bs=64 >/dev/null 2>&1 </dev/null &
  awake=$!
fi

if [ -z "$DL_APP_ONLY" ] || ! command -v aria2c >/dev/null || ! command -v yt-dlp >/dev/null ||
    ! command -v ffmpeg >/dev/null || ! command -v python3 >/dev/null; then
  echo "Installing aria2, yt-dlp, Node and ffmpeg. The first time, this downloads about 150 MB."
  apk add -q aria2 curl ffmpeg nodejs python3 yt-dlp-ejs-rt-quickjs yt-dlp ||
    apk add -q aria2 curl ffmpeg nodejs python3 yt-dlp ||
    echo "Couldn't install everything; carrying on with what's there."

  # yt-dlp's own release, next to Alpine's: YouTube changes often, Alpine's package lags
  # behind, and only this one can update itself (dl runs `yt-dlp -U` once a day).
  echo "Installing the latest yt-dlp from its own releases."
  if curl -fsSL -m 300 -o /usr/local/bin/yt-dlp.new \\
      https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp; then
    chmod +x /usr/local/bin/yt-dlp.new
    mv -f /usr/local/bin/yt-dlp.new /usr/local/bin/yt-dlp
  else
    rm -f /usr/local/bin/yt-dlp.new
    echo "Couldn't download it; using Alpine's yt-dlp for now."
  fi
  yt-dlp --version >/root/Downloads/.logs/.yt-dlp-version 2>/dev/null
  date +%s >/root/Downloads/.logs/.updated
fi

# The list's format changed in version 2 of dl. Downloads from an older dl would keep going
# the old way, so stop them and start the list afresh, once. Their files stay, and sharing
# the same link again carries on where they stopped.
if [ ! -e /root/Downloads/.logs/.v2 ]; then
  pkill -x aria2c
  rm -f /root/Downloads/.logs/*
fi

# "=== app" lines say what's happening, in Settings, while dl's update runs this.
echo "=== app Installing the new version"
# Write the new dl next to the old one and swap them in one step: a download that's running
# keeps reading the old file, where overwriting it in place would break it mid-run.
cat >/usr/local/bin/dl.new <<'DL_SCRIPT'
{dl}DL_SCRIPT
chmod +x /usr/local/bin/dl.new
mv -f /usr/local/bin/dl.new /usr/local/bin/dl
# The pictures in dl's menus: a name and a base64 PNG on each line.
mkdir -p /usr/local/share/dl/icons
while read -r icon data; do
  printf '%s' "$data" >"/usr/local/share/dl/icons/$icon.b64"
done <<'ICONS'
{icons}ICONS
# The live view's server, which dl starts when it's asked for. A running one stops now, so
# that the next one is the new one.
cat >/usr/local/share/dl/web.py.new <<'WEB_PY'
{web}WEB_PY
mv -f /usr/local/share/dl/web.py.new /usr/local/share/dl/web.py
pkill -f /usr/local/share/dl/web.py
# What turns yt-dlp's list of a video's qualities into dl's menu (Choose the quality).
cat >/usr/local/share/dl/formats.py.new <<'FORMATS_PY'
{formats}FORMATS_PY
mv -f /usr/local/share/dl/formats.py.new /usr/local/share/dl/formats.py
touch /root/Downloads/.logs/.v2
# dl's update compares the repository's copy of this script against this hash.
sha256sum <"$0" | cut -d' ' -f1 >/root/Downloads/.logs/.setup
echo "Installed dl."

# The shortcut only needs importing again when it changed: {version} identifies this one.
mkdir -p /root/Shortcuts
cd /root/Shortcuts || exit 1
rm -f "Download with aria2.shortcut" "Download Status.shortcut" "Stop Downloads.shortcut"
new_shortcut=
if [ "$(cat .version 2>/dev/null)" = {version} ] && [ -e {name}.shortcut ]; then
  echo "The {name} shortcut hasn't changed: no need to import it again."
else
  echo "=== app Signing the new shortcut"
  if ! curl -sS -m 90 -X POST -H 'Content-Type: application/json' --data-binary @- \\
      https://hubsign.routinehub.services/sign -o {name}.shortcut.new <<'EOF'
{request}
EOF
  then
    echo "FAILED to sign the shortcut: no answer from HubSign."
  elif [ "$(head -c 4 {name}.shortcut.new)" = AEA1 ]; then
    mv -f {name}.shortcut.new {name}.shortcut
    echo {version} >.version
    new_shortcut=/root/Shortcuts/{name}.shortcut
    # Also into the Files folder mounted at /mnt/phone, always as {name}.shortcut, in place
    # of the one before: copied in under another name first, because writing into a file
    # that Files has open there can hang. Builds before used to be {name}-<version>.shortcut.
    if awk '$2 == "/mnt/phone" { found = 1 } END { exit !found }' /proc/mounts 2>/dev/null; then
      timeout 60 rm -f /mnt/phone/{name}-*.shortcut
      if timeout 60 cp {name}.shortcut /mnt/phone/.{name}.shortcut.new &&
          timeout 60 mv -f /mnt/phone/.{name}.shortcut.new /mnt/phone/{name}.shortcut; then
        new_shortcut=/mnt/phone/{name}.shortcut
      fi
    fi
    # The shortcut, when it next opens, offers the new one by itself. dl's menu shows it
    # until the new shortcut has been imported, which it can tell from the version.
    echo "$new_shortcut" >.pending
    echo "Signed the new {name} shortcut."
  else
    echo "FAILED to sign the shortcut: $(head -c 300 {name}.shortcut.new)"
  fi
  rm -f /root/Shortcuts/{name}.shortcut.new
fi
cd /root || exit 1
[ -n "$awake" ] && kill $awake 2>/dev/null

echo
dl -v

echo
echo "Setup finished."
case $new_shortcut in
  /mnt/phone/*) echo "Next: in Files, open the folder you mounted at /mnt/phone and tap {name}.shortcut." ;;
  /root/*) echo "Next: in Files, tap iSH-AOK -> (Alpine) -> root -> Shortcuts -> {name}.shortcut." ;;
esac
[ -n "$new_shortcut" ] && echo "Add it, or choose Replace if you already have the {name} shortcut."
cat <<'DONE'
If you haven't yet: Settings -> Apps -> iSH-AOK -> Location: choose Always, and turn
Precise Location off to save battery. Without Always, downloads only run while iSH-AOK is open.
DONE
"""


def hubsign_request(name, plist):
    # HubSign takes the shortcut as an XML plist string (see Cherri's signing.go).
    xml = re.sub(rb">\s+<", b"><", plistlib.dumps(plist, fmt=plistlib.FMT_XML)).decode()
    return json.dumps({"shortcutName": name, "shortcut": xml})


def build(version):
    global _uuids
    _uuids = itertools.count(1)  # the same UUIDs on every build
    return aria2(version)


def binary(plist):
    return plistlib.dumps(plist, fmt=plistlib.FMT_BINARY)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    # The version is a hash of the shortcut built without one, so it changes whenever
    # anything else in the shortcut does.
    version = f"{LEVEL}-" + hashlib.sha256(binary(build(""))).hexdigest()[:8]
    plist = build(version)
    path = OUT / f"{NAME}.shortcut"
    path.write_bytes(binary(plist))
    print(path, version)

    # The pictures for dl's menus, also written to icons/ to look at.
    (HERE / "icons").mkdir(exist_ok=True)
    pictures = ""
    for name, png in icons.icons().items():
        (HERE / "icons" / f"{name}.png").write_bytes(png)
        pictures += f"{name} {base64.b64encode(png).decode()}\n"

    path = OUT / "setup-on-phone.sh"
    dl = (HERE / "dl").read_text()
    setup = (SETUP.replace("{name}", NAME).replace("{version}", version)
             .replace("{request}", hubsign_request(NAME, plist)))
    web, formats = (HERE / "web.py").read_text(), (HERE / "formats.py").read_text()
    path.write_text(setup.replace("{icons}", pictures).replace("{dl}", dl).replace("{web}", web)
                    .replace("{formats}", formats))  # last: they're big
    print(path)
