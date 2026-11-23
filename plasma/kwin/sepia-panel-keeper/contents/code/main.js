// The conky panel is a desktop-type window, so it stays visible on Show Desktop
// and sits under normal windows. Plasma's own desktop windows share that layer
// and cover it whenever they appear or get clicked, so raise the panel again.
function isPanel(w) {
    return w.desktopWindow && String(w.resourceClass).toLowerCase() === "conky";
}

function raisePanels() {
    workspace.stackingOrder.filter(isPanel).forEach(function (w) {
        workspace.raiseWindow(w);
    });
}

workspace.windowAdded.connect(function (w) {
    if (w.desktopWindow) raisePanels();
});

workspace.windowActivated.connect(function (w) {
    if (w && w.desktopWindow) raisePanels();
});

raisePanels();
