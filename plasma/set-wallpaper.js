// Run through plasmashell's evaluateScript (install.sh does this).
// Picks the right sepia-mountains image for each monitor automatically:
//   2 monitors  -> the dual image split across them (left half / right half)
//   1 ultrawide -> the ultrawide image
//   otherwise   -> the single-screen image
var dir = "@WPDIR@";
var live = "@LIVE@" === "1";   // use the live (visualiser) wallpaper plugin
var ds = desktops();
var screensSeen = {};
var list = [];
for (var i = 0; i < ds.length; i++) {
    var g = screenGeometry(ds[i].screen);
    list.push({ d: ds[i], g: g });
    screensSeen[ds[i].screen] = g;
}
var xs = [];
for (var s in screensSeen) xs.push(screensSeen[s].x);
xs.sort(function (a, b) { return a - b; });
var n = xs.length;

function set(d, file, visualiser) {
    var front = file.replace(".png", "_front.png");
    if (live) {
        d.wallpaperPlugin = "com.nexuskiwi.sepiasummit";
        d.currentConfigGroup = ["Wallpaper", "com.nexuskiwi.sepiasummit", "General"];
        d.writeConfig("Background", "file://" + dir + "/" + file);
        d.writeConfig("Foreground", "file://" + dir + "/" + front);
        d.writeConfig("Visualiser", visualiser);
    } else {
        d.wallpaperPlugin = "org.kde.image";
        d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        d.writeConfig("Image", "file://" + dir + "/" + file);
        d.writeConfig("FillMode", 2); // scaled & cropped
    }
}

for (var j = 0; j < list.length; j++) {
    var g = list[j].g;
    var tall = g.height > 1150 ? "1440" : "1080";
    var file;
    var visualiser = true;   // with two monitors, only the right one gets the bars
    if (n === 2) {
        var side = (g.x === xs[0]) ? "LEFT" : "RIGHT";
        visualiser = side === "RIGHT";
        file = (tall === "1440" ? "sepia-mountains_dual-1440p_5120x1440_" : "sepia-mountains_dual-1080p_3840x1080_") + side + ".png";
    } else if (g.width / g.height >= 2.2) {
        file = tall === "1440" ? "sepia-mountains_ultrawide_3440x1440.png" : "sepia-mountains_ultrawide_2560x1080.png";
    } else {
        file = tall === "1440" ? "sepia-mountains_single_2560x1440.png" : "sepia-mountains_single_1920x1080.png";
    }
    set(list[j].d, file, visualiser);
    print("screen " + list[j].d.screen + " (" + g.width + "x" + g.height + " @ x=" + g.x + ") -> " + file);
}
