#!/usr/bin/env python3
"""Build the "aria2" shortcut, plus the script that sets everything up on the phone.

Writes into shortcuts/:
  aria2.shortcut      unsigned; to use it directly, sign it on a Mac:
                      shortcuts sign -m anyone -i aria2.shortcut -o "aria2 (signed).shortcut"
  setup-on-phone.sh   run in iSH-AOK: installs aria2, yt-dlp and dl, asks for location access,
                      then signs the shortcut with RoutineHub's HubSign service into
                      /root/Shortcuts

The iSH-AOK identifiers below come from its source (github.com/emkey1/ish-AOK):
app/ISHRunCommandIntent.swift for the intent and its parameters, and
fastlane/Appfile for the bundle ID and team ID of the TestFlight build.
The plist layout follows Cherri's encoders (github.com/electrikmilk/cherri).
"""
import hashlib
import itertools
import json
import plistlib
import re
import uuid
from pathlib import Path

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
# If conditions, as numbered by the Shortcuts app.
CONTAINS, HAS_ANY_VALUE = 99, 100
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


def run_command(*command):
    return action("app.ish.iSH-AOK.ISHRunCommandIntent",
                  AppIntentDescriptor={**ISH_AOK, "AppIntentIdentifier": "ISHRunCommandIntent"},
                  command=text(*command))


def run_with_base64(command, variable):
    """Run `<command> '<variable, base64-encoded>'`, so nothing in it can act as shell syntax."""
    as_text = action("gettext", WFTextActionText=text(variable))
    encoded = action("base64encode", WFEncodeMode="Encode", WFInput=attachment(output_of(as_text, "Text")))
    run = run_command(f"{command} '", output_of(encoded, "Base64 Encoded"), "'")
    return [as_text, encoded, run], run


def notify(run):
    return action("notification", WFNotificationActionTitle="aria2",
                  WFNotificationActionBody=text(output_of(run, "Run Command")))


def open_ish_aok():
    return action("openapp", WFAppIdentifier=ISH_AOK["BundleIdentifier"], WFSelectedApp=ISH_AOK)


def aria2():
    acts = []

    # Shared from another app: start the download and say so. It carries on in the
    # background as long as iSH-AOK may use location Always (see keep_awake in dl).
    shared = new_uuid()
    start, run = run_with_base64("dl -b", SHORTCUT_INPUT)
    acts += [if_(shared, SHORTCUT_INPUT, HAS_ANY_VALUE), *start, notify(run),
             action("exit"), control("conditional", shared, END)]

    # Opened on its own: the download list, shown again after every choice until Close.
    loop = new_uuid()
    menu = run_command("dl -m")
    lines = action("text.split", text=text(output_of(menu, "Run Command")), WFTextSeparator="New Lines")
    choose = action("choosefromlist", WFInput=attachment(output_of(lines, "Split Text")),
                    WFChooseFromListActionPrompt="Tap a download to pause or resume it.")
    chosen = output_of(choose, "Chosen Item")
    acts += [control("repeat.count", loop, START, WFRepeatCount=200), menu, lines, choose]

    # dl -m lists these three, but only the Shortcut can do them.
    close, open_app, add = new_uuid(), new_uuid(), new_uuid()
    acts += [if_(close, chosen, CONTAINS, "❌"), action("exit"), control("conditional", close, END)]
    acts += [if_(open_app, chosen, CONTAINS, "📲"), open_ish_aok(), action("exit"),
             control("conditional", open_app, END)]
    clipboard = action("getclipboard")
    from_clipboard, run = run_with_base64("dl -b", output_of(clipboard, "Clipboard"))
    # Anything else (a download, Pause all, Resume all, Clear finished, Refresh) is dl's to do.
    other, _ = run_with_base64("dl -a -b", chosen)
    acts += [if_(add, chosen, CONTAINS, "➕"), clipboard, *from_clipboard, notify(run),
             control("conditional", add, MIDDLE), *other, control("conditional", add, END)]

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
# for YouTube, and ffmpeg for joining video and audio), curl and the dl script; asks for
# location access, which keeps downloads going in the background; then signs the "aria2"
# shortcut with RoutineHub's HubSign service (the signer Cherri and RoutineHub tools use)
# and saves it in Files -> iSH-AOK -> (Alpine) -> root -> Shortcuts.
# dl runs the newest copy of this script from the project's repository when it changes.
# Generated by build_shortcuts.py.

# Location updates are what keep iSH-AOK running when it's not on screen, so start them
# first: then the install below carries on if you leave the app. The first time, iOS asks.
# A download may already be keeping them going; then leave that alone.
echo "iSH-AOK will ask for location access: allow it. It keeps this setup going if you leave"
echo "the app, and later keeps downloads going in the background."
awake=
if ! pgrep -f 'dd if=/dev/location' >/dev/null; then
  nohup dd if=/dev/location of=/dev/null bs=64 >/dev/null 2>&1 </dev/null &
  awake=$!
fi

echo "Installing aria2, yt-dlp, Node and ffmpeg. The first time, this downloads about 150 MB."
apk add -q aria2 curl ffmpeg nodejs yt-dlp-ejs-rt-quickjs yt-dlp ||
  apk add -q aria2 curl ffmpeg nodejs yt-dlp ||
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

# The list's format changed in version 2 of dl. Downloads from an older dl would keep going
# the old way, so stop them and start the list afresh, once. Their files stay, and sharing
# the same link again carries on where they stopped.
if [ ! -e /root/Downloads/.logs/.v2 ]; then
  pkill -x aria2c
  rm -f /root/Downloads/.logs/*
fi

# Write the new dl next to the old one and swap them in one step: a download that's running
# keeps reading the old file, where overwriting it in place would break it mid-run.
cat >/usr/local/bin/dl.new <<'DL_SCRIPT'
{dl}DL_SCRIPT
chmod +x /usr/local/bin/dl.new
mv -f /usr/local/bin/dl.new /usr/local/bin/dl
mkdir -p /root/Downloads/.logs
touch /root/Downloads/.logs/.v2
date +%s >/root/Downloads/.logs/.updated
# dl's daily update compares the repository's copy of this script against this hash.
sha256sum <"$0" | cut -d' ' -f1 >/root/Downloads/.logs/.setup
echo "Installed dl."

# The shortcut only needs importing again when it changed: {version} identifies this one.
mkdir -p /root/Shortcuts
cd /root/Shortcuts || exit 1
rm -f "Download with aria2.shortcut" "Download Status.shortcut" "Stop Downloads.shortcut"
new_shortcut=
if [ "$(cat .version 2>/dev/null)" = {version} ] && [ -e {name}.shortcut ]; then
  echo "The {name} shortcut hasn't changed: no need to import it again."
elif ! curl -sS -m 90 -X POST -H 'Content-Type: application/json' --data-binary @- \\
    https://hubsign.routinehub.services/sign -o {name}.shortcut <<'EOF'
{request}
EOF
then
  echo "FAILED to sign the shortcut: no answer from HubSign."
elif [ "$(head -c 4 {name}.shortcut)" = AEA1 ]; then
  echo {version} >.version
  new_shortcut="Files -> iSH-AOK -> (Alpine) -> root -> Shortcuts -> {name}.shortcut"
  # Also put it in the Files folder mounted at /mnt/phone, under a name of its own: writing
  # over a file that Files has open there can hang.
  if awk '$2 == "/mnt/phone" { found = 1 } END { exit !found }' /proc/mounts 2>/dev/null &&
      timeout 60 cp {name}.shortcut /mnt/phone/{name}-{version}.shortcut; then
    new_shortcut="Files -> On My iPhone -> Downloads -> {name}-{version}.shortcut"
  fi
  # The download list shows where it is until it's tapped: an update may run this unseen.
  echo "$new_shortcut" >/root/Shortcuts/.pending
  echo "Signed the new {name} shortcut."
else
  echo "FAILED to sign the shortcut: $(head -c 300 {name}.shortcut)"
  rm -f /root/Shortcuts/{name}.shortcut
fi
cd /root || exit 1
[ -n "$awake" ] && kill $awake 2>/dev/null

echo
dl -v

echo
echo "Setup finished."
if [ -n "$new_shortcut" ]; then
  echo "Next: import the new shortcut. Tap $new_shortcut and choose Replace."
fi
cat <<'DONE'
If you haven't yet: Settings -> Apps -> iSH-AOK -> Location: choose Always, and turn
Precise Location off to save battery. Without Always, downloads only run while iSH-AOK is open.
DONE
"""


def hubsign_request(name, plist):
    # HubSign takes the shortcut as an XML plist string (see Cherri's signing.go).
    xml = re.sub(rb">\s+<", b"><", plistlib.dumps(plist, fmt=plistlib.FMT_XML)).decode()
    return json.dumps({"shortcutName": name, "shortcut": xml})


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    plist = aria2()
    path = OUT / f"{NAME}.shortcut"
    path.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_BINARY))
    print(path)
    path = OUT / "setup-on-phone.sh"
    dl = (HERE / "dl").read_text()
    version = hashlib.sha256(plistlib.dumps(plist, fmt=plistlib.FMT_BINARY)).hexdigest()[:8]
    path.write_text(SETUP.replace("{dl}", dl).replace("{name}", NAME).replace("{version}", version)
                    .replace("{request}", hubsign_request(NAME, plist)))
    print(path)
