// Reports the page to Swift as plain data: the DOM Readability chose, and what the markup says about the article.

const MR_ATTRIBUTES = new Set([
    "href", "src", "srcset", "alt", "title", "id", "class", "role", "colspan", "rowspan", "start", "type", "lang",
    "dir", "datetime", "width", "height", "aria-label", "epub:type", "itemprop", "data-fn", "data-src", "data-srcset",
]);

function mrNode(node) {
    if (node.nodeType === 3) return { tag: "#text", text: node.nodeValue };
    if (node.nodeType !== 1) return null;
    const attrs = {};
    for (const attribute of node.attributes) {
        if (MR_ATTRIBUTES.has(attribute.name) || attribute.name.startsWith("data-mr-")) attrs[attribute.name] = attribute.value;
    }
    const children = [];
    for (const child of node.childNodes) {
        const serialized = mrNode(child);
        if (serialized) children.push(serialized);
    }
    return { tag: node.tagName.toLowerCase(), attrs, children };
}

function mrMetadata(doc) {
    const meta = [];
    for (const tag of doc.querySelectorAll("meta")) {
        const key = tag.getAttribute("name") || tag.getAttribute("property") || tag.getAttribute("itemprop") || tag.getAttribute("http-equiv");
        if (key) meta.push({ key: key.toLowerCase(), content: tag.getAttribute("content") || "" });
    }
    const canonical = doc.querySelector("link[rel~=canonical]");
    return {
        title: doc.title || "",
        meta,
        canonicalURL: canonical ? canonical.getAttribute("href") : null,
        headings: Array.from(doc.querySelectorAll("h1"), (heading) => heading.textContent.trim()).slice(0, 5),
        language: doc.documentElement.getAttribute("lang"),
        direction: doc.documentElement.getAttribute("dir"),
        baseURL: doc.baseURI,
    };
}

function mrExtract() {
    // Before pruning: text the page's stylesheet hides is still part of the story when its structured data says so.
    const paragraphs = Array.from(document.querySelectorAll("p"), (p) => p.textContent.replace(/\s+/g, " ").trim()).filter((text) => text.length >= 25);
    mrPrepare(document);
    const metadata = mrMetadata(document);
    const article = new Readability(document.cloneNode(true), { keepClasses: true, serializer: (element) => element }).parse();
    const readability = article && {
        content: mrNode(article.content),
        title: article.title,
        byline: article.byline,
        excerpt: article.excerpt,
        siteName: article.siteName,
        publishedTime: article.publishedTime,
    };
    return JSON.stringify({ readability, metadata, body: mrNode(document.body), paragraphs });
}
