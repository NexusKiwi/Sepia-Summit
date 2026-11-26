// Run through plasmashell's evaluateScript (install.sh does this).
// One floating glass dock down the left edge of the leftmost monitor, no panel on the others,
// and desktop icons hidden from view (the files stay; they appear in the drawer).
// @LAUNCHERS@ = the pinned apps install.sh found (browser, files, terminal, Steam, Discord, Claude).
// @TRAY_BUTTONS@ = tray apps that get their own button under the tray arrow (OpenRGB if it runs).
var ps = panels();
var leftScreen = 0, leftX = Infinity;
for (var s = 0; s < screenCount; s++) {
    var g = screenGeometry(s);
    if (g.x < leftX) { leftX = g.x; leftScreen = s; }
}

var dock = null;
for (var i = 0; i < ps.length; i++) {
    if (ps[i].screen === leftScreen && !dock) dock = ps[i];
}
if (!dock) { dock = new Panel; dock.screen = leftScreen; dock.location = "left"; }
for (var j = 0; j < ps.length; j++) {
    if (ps[j].id !== dock.id) ps[j].remove();
}

// Top to bottom: drawer, pinned and open apps, the tray arrow, then volume, network and the tray
// buttons. The tray always draws its arrow after its icons, so it keeps none of its own and the
// icons that should stay visible are separate widgets below it. The clock lives on the stats panel.
var drawer = null, tasks = null, tray = null, volume = null, network = null, buttons = {};
var wantButtons = "@TRAY_BUTTONS@".charAt(0) === "@" ? [] : "@TRAY_BUTTONS@".split(",").filter(function (b) { return b; });
dock.widgets().forEach(function (w) {
    if (w.type === "org.kde.plasma.systemtray" && !tray) tray = w;
    else if (w.type === "com.nexuskiwi.sepiadrawer" && !drawer) drawer = w;
    else if (w.type === "org.kde.plasma.icontasks" && !tasks) tasks = w;
    else if (w.type === "org.kde.plasma.volume" && !volume) volume = w;
    else if (w.type === "org.kde.plasma.networkmanagement" && !network) network = w;
    else if (w.type === "com.nexuskiwi.sepiatrayitem") {
        w.currentConfigGroup = ["General"];
        var id = String(w.readConfig("itemId", "OpenRGB"));
        if (!buttons[id]) { buttons[id] = w; if (wantButtons.indexOf(id) < 0) wantButtons.push(id); } else w.remove();
    }
    else w.remove();   // includes the end spacers older docks had
});
if (!drawer) drawer = dock.addWidget("com.nexuskiwi.sepiadrawer");
if (!tasks) tasks = dock.addWidget("org.kde.plasma.icontasks");
if (!tray) tray = dock.addWidget("org.kde.plasma.systemtray");
if (!volume) volume = dock.addWidget("org.kde.plasma.volume");
if (!network) network = dock.addWidget("org.kde.plasma.networkmanagement");
wantButtons.forEach(function (id) {
    if (buttons[id]) return;
    var b = dock.addWidget("com.nexuskiwi.sepiatrayitem");
    b.currentConfigGroup = ["General"];
    b.writeConfig("itemId", id);
    b.writeConfig("icon", id);
    b.writeConfig("label", id);
    buttons[id] = b;
});

// Fold every tray icon behind the tray's arrow. install.sh fills in running app icons.
tray.currentConfigGroup = ["General"];
var hidden = {};
String(tray.readConfig("knownItems", "")).split(",")
    .concat(String(tray.readConfig("extraItems", "")).split(","))
    .concat(String(tray.readConfig("hiddenItems", "")).split(","))
    .concat(String(tray.readConfig("shownItems", "")).split(","))
    .concat("@TRAY_ITEMS@".split(","))
    .forEach(function (item) { if (item && item.charAt(0) !== "@") hidden[item] = true; });
tray.writeConfig("hiddenItems", Object.keys(hidden).join(","));
tray.writeConfig("shownItems", "");
tray.writeConfig("scaleIconsToFit", false);  // keeps the arrow at its usual small size

tasks.currentConfigGroup = ["General"];
var pinned = "@LAUNCHERS@".charAt(0) === "@" ? "" : "@LAUNCHERS@";
tasks.writeConfig("launchers", pinned);
tasks.writeConfig("iconSpacing", 2);
tasks.writeConfig("showOnlyCurrentScreen", false);
tasks.writeConfig("showOnlyCurrentDesktop", false);

dock.currentConfigGroup = ["General"];
dock.writeConfig("AppletOrder", [drawer.id, tasks.id, tray.id, volume.id, network.id]
    .concat(wantButtons.map(function (id) { return buttons[id].id; })).join(";"));
dock.location = "left";
dock.height = 46;               // thickness, for a side panel: icons a little smaller than the drawer's
dock.floating = true;
dock.hiding = "dodgewindows";   // shown until a window covers it; maximised windows fill the screen
dock.lengthMode = "fit";
dock.alignment = "center";
dock.opacity = "translucent";   // the Plasma style + KWin blur make it frosted glass

desktops().forEach(function (d) {
    d.currentConfigGroup = ["General"];
    d.writeConfig("filterMode", 2);     // hide files matching the pattern
    d.writeConfig("filterPattern", "*");
    d.reloadConfig();
});
print("dock on screen " + leftScreen + ": " + dock.widgets().map(function (w) { return w.type; }).join(", "));
