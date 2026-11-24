// Run through plasmashell's evaluateScript (install.sh does this).
// One floating dock on the leftmost monitor, no panel on the others,
// and desktop icons hidden from view (the files stay; they appear in the drawer).
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
if (!dock) { dock = new Panel; dock.screen = leftScreen; dock.location = "bottom"; }
for (var j = 0; j < ps.length; j++) {
    if (ps[j].id !== dock.id) ps[j].remove();
}

// The dock is only: drawer, open apps, tray. The clock lives on the stats panel.
// A fixed spacer at each end makes it a little wider, and with it the strip
// along the bottom edge that brings it back up.
var drawer = null, tasks = null, tray = null, spacers = [];
dock.widgets().forEach(function (w) {
    if (w.type === "org.kde.plasma.panelspacer" && spacers.length < 2) spacers.push(w);
    else if (w.type === "org.kde.plasma.systemtray" && !tray) tray = w;
    else if (w.type === "com.nexuskiwi.sepiadrawer" && !drawer) drawer = w;
    else if (w.type === "org.kde.plasma.icontasks" && !tasks) tasks = w;
    else w.remove();
});
if (!drawer) drawer = dock.addWidget("com.nexuskiwi.sepiadrawer");
if (!tasks) tasks = dock.addWidget("org.kde.plasma.icontasks");
if (!tray) tray = dock.addWidget("org.kde.plasma.systemtray");
while (spacers.length < 2) spacers.push(dock.addWidget("org.kde.plasma.panelspacer"));
spacers.forEach(function (sp) {
    sp.currentConfigGroup = ["General"];
    sp.writeConfig("expanding", false);
    sp.writeConfig("length", 80);
});

// Fold every tray icon behind the tray's arrow. install.sh fills in running app icons.
tray.currentConfigGroup = ["General"];
var hidden = {};
String(tray.readConfig("knownItems", "")).split(",")
    .concat(String(tray.readConfig("extraItems", "")).split(","))
    .concat(String(tray.readConfig("hiddenItems", "")).split(","))
    .concat("@TRAY_ITEMS@".split(","))
    .forEach(function (item) { if (item && item.charAt(0) !== "@") hidden[item] = true; });
tray.writeConfig("hiddenItems", Object.keys(hidden).join(","));
tray.writeConfig("shownItems", "");
tray.writeConfig("scaleIconsToFit", true);   // makes the arrow's slot square, like the drawer button

tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "");   // nothing pinned: the dock only shows what's open
tasks.writeConfig("showOnlyCurrentScreen", false);
tasks.writeConfig("showOnlyCurrentDesktop", false);

dock.currentConfigGroup = ["General"];
dock.writeConfig("AppletOrder", [spacers[0].id, drawer.id, tasks.id, tray.id, spacers[1].id].join(";"));
dock.location = "bottom";
dock.height = 52;
dock.floating = true;
dock.hiding = "dodgewindows";   // shown until a window covers it; maximised windows fill the screen
dock.lengthMode = "fit";
dock.alignment = "center";
dock.opacity = "translucent";

desktops().forEach(function (d) {
    d.currentConfigGroup = ["General"];
    d.writeConfig("filterMode", 2);     // hide files matching the pattern
    d.writeConfig("filterPattern", "*");
    d.reloadConfig();
});
print("dock on screen " + leftScreen + ": " + dock.widgets().map(function (w) { return w.type; }).join(", "));
