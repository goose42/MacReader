// Prepares the live document before Readability copies it. Everything here reads the rendered page, which only the web
// view can give us: what a stylesheet hides, what floats over the text, which font a block is set in. Deciding what
// the article is happens later, in Swift.

const MR_JUNK_TOKENS = new Set([
    "ad", "ads", "advert", "advertisement", "adslot", "adsbygoogle", "dfp", "gpt", "sponsor", "sponsored", "promo", "promoted",
    "outbrain", "taboola", "newsletter", "subscribe", "subscription", "signup", "paywall", "regwall", "piano", "cookie",
    "cookies", "consent", "gdpr", "ccpa", "cmp", "onetrust", "didomi", "share", "sharing", "social", "related", "recommended",
    "popup", "modal", "overlay", "interstitial", "toast", "comment", "comments", "disqus", "sidebar", "breadcrumb",
    "breadcrumbs",
]);
const MR_JUNK_PHRASES = [" more stories ", " read next ", " also read ", " you may like ", " top stories ", " trending now "];
const MR_AD_SIZES = /(?:^|[^0-9])(?:300x250|728x90|160x600|300x600|320x50|320x100|970x250|970x90|336x280|468x60)(?:[^0-9]|$)/;
const MR_AD_ATTRIBUTES = ["data-ad", "data-ad-slot", "data-ad-client", "data-ad-unit", "data-adunit", "data-google-query-id"];
const MR_JUNK_ROLES = new Set(["banner", "contentinfo", "search", "alertdialog", "dialog", "alert", "menu", "menubar"]);
const MR_NEVER_TESTED = new Set(["html", "body", "head", "script", "style", "link", "meta", "noscript", "title", "template"]);
const MR_MONOSPACE = /mono|courier|consolas|menlo|source code|fira code/i;

/** Words of a class or id, split at punctuation and camelCase, so "ad" matches "ad-top" but not "download". */
function mrTokens(text) {
    return text.replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
}

function mrIsJunk(element, style) {
    const tag = element.tagName.toLowerCase();
    if (style.display === "none" || style.visibility === "hidden" || element.hasAttribute("hidden")) return true;
    if (element.getAttribute("aria-hidden") === "true" && !["img", "svg", "picture"].includes(tag)) return true;
    if (element.getAttribute("aria-modal") === "true") return true;
    if (style.position === "fixed" || style.position === "sticky") return true;
    if (tag === "nav" || tag === "dialog") return true;
    if ((tag === "form" || tag === "fieldset") && element.querySelector("input, button, textarea, select")) return true;
    if (MR_JUNK_ROLES.has(element.getAttribute("role"))) return true;
    if (MR_AD_ATTRIBUTES.some((name) => element.hasAttribute(name))) return true;

    const id = element.id || "";
    const className = typeof element.className === "string" ? element.className : "";
    if (id.startsWith("div-gpt-ad") || (tag === "ins" && className.includes("adsbygoogle"))) return true;
    if (MR_AD_SIZES.test(id + " " + className)) return true;

    const tokens = mrTokens(id).concat(mrTokens(className));
    if (tokens.some((token) => MR_JUNK_TOKENS.has(token))) return true;
    const phrase = " " + tokens.join(" ") + " ";
    return MR_JUNK_PHRASES.some((junk) => phrase.includes(junk));
}

/** Asides inside the article are notes worth reading. Readability drops every aside and flattens divs, so they
 *  become an element of our own, which it leaves alone. */
function mrKeepArticleAsides(doc) {
    for (const aside of doc.querySelectorAll("article aside, main aside")) {
        const callout = doc.createElement("mr-callout");
        while (aside.firstChild) callout.appendChild(aside.firstChild);
        aside.replaceWith(callout);
    }
}

/** Elements the bundled ad-blocker filter lists hide. A rule applies only if the page has the class or id it is keyed
 *  by, so the tens of thousands of rules cost one pass over the page's names. */
function mrCosmeticJunk(doc) {
    const classes = new Set(MR_COSMETIC.classes);
    const ids = new Set(MR_COSMETIC.ids);
    const found = new Set();
    const tokens = new Set();
    for (const element of doc.body.querySelectorAll("*")) {
        if (typeof element.className === "string") {
            for (const name of element.classList) {
                if (classes.has(name)) found.add(element);
                tokens.add("." + name);
            }
        }
        if (element.id) {
            if (ids.has(element.id)) found.add(element);
            tokens.add("#" + element.id);
        }
    }
    for (const token of tokens) {
        if (!Object.prototype.hasOwnProperty.call(MR_COSMETIC.complex, token)) continue;
        for (const selector of MR_COSMETIC.complex[token]) {
            try {
                for (const element of doc.body.querySelectorAll(selector)) found.add(element);
            } catch (error) {
                // A selector this engine can't parse is skipped, not fatal.
            }
        }
    }
    return Array.from(found).filter((element) => !mrHoldsArticleElement(element));
}

function mrHoldsArticleElement(element) {
    const selector = "article, main, [itemprop~=articleBody]";
    return element.matches(selector) || element.querySelector(selector) !== null;
}

function mrRemoveJunk(doc) {
    const paragraphLength = (root) => Array.from(root.querySelectorAll("p"), (p) => p.textContent.length).reduce((a, b) => a + b, 0);
    const paragraphTotal = paragraphLength(doc.body);
    // With almost no paragraph text to go by, fall back to all text.
    const textTotal = paragraphTotal >= 200 ? paragraphTotal : doc.body.textContent.length;
    const share = (element) => (paragraphTotal >= 200 ? paragraphLength(element) : element.textContent.length) / Math.max(textTotal, 1);

    const junk = [];
    for (const element of doc.body.querySelectorAll("*")) {
        if (MR_NEVER_TESTED.has(element.tagName.toLowerCase())) continue;
        if (mrIsJunk(element, doc.defaultView.getComputedStyle(element))) junk.push(element);
    }
    junk.push(...mrCosmeticJunk(doc));
    // Something broad enough to hold the article is mislabelled, not junk.
    for (const element of junk) {
        if (element.isConnected && share(element) <= 0.3) element.remove();
    }
}

/** Marks monospaced text. A div or paragraph set in a monospaced font that keeps its whitespace is code; Readability
 *  flattens such blocks and loses their attributes, so they become a real `pre`. */
function mrMarkRenderedStyles(doc) {
    for (const element of Array.from(doc.body.querySelectorAll("pre, code, kbd, samp, tt, div, p, td"))) {
        const style = doc.defaultView.getComputedStyle(element);
        const isMonospace = MR_MONOSPACE.test(style.fontFamily);
        const keepsWhitespace = /^pre/.test(style.whiteSpace);
        const tag = element.tagName.toLowerCase();
        if (isMonospace && keepsWhitespace && (tag === "div" || tag === "p") && !element.querySelector("p, div, pre, ul, ol, table")) {
            const code = doc.createElement("pre");
            while (element.firstChild) code.appendChild(element.firstChild);
            code.setAttribute("data-mr-mono", "1");
            element.replaceWith(code);
            continue;
        }
        if (isMonospace) element.setAttribute("data-mr-mono", "1");
        if (keepsWhitespace) element.setAttribute("data-mr-pre", "1");
    }
}

function mrPrepare(doc) {
    mrKeepArticleAsides(doc);
    mrRemoveJunk(doc);
    mrMarkRenderedStyles(doc);
}
