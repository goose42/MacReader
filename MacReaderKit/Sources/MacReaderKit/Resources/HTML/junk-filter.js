// Prepares the live document before Readability copies it: marks what only the rendered page can tell us.
// Everything here reads the page; deciding what to keep happens in Swift.

function mrPrepare(doc) {
    const monospace = /mono|courier|consolas|menlo|source code|fira code/i;
    for (const element of doc.body.querySelectorAll("pre, code, kbd, samp, tt, div, p, td")) {
        const style = doc.defaultView.getComputedStyle(element);
        if (monospace.test(style.fontFamily)) element.setAttribute("data-mr-mono", "1");
        if (/^pre/.test(style.whiteSpace)) element.setAttribute("data-mr-pre", "1");
    }
}
