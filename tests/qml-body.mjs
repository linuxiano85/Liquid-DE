// Extract production JS bodies; this does not load QML.
export function body(text, marker) {
    const at = text.indexOf(marker);
    if (at < 0) throw new Error(`Missing source marker ${marker}`);
    const first = text.indexOf('{', at);
    let depth = 0, quote = '', comment = '';
    for (let i = first; i < text.length; i++) {
        const c = text[i], n = text[i + 1];
        if (comment === 'line') { if (c === '\n') comment = ''; }
        else if (comment === 'block') { if (c === '*' && n === '/') { comment = ''; i++; } }
        else if (quote) { if (c === '\\') i++; else if (c === quote) quote = ''; }
        else if ('\"\'`'.includes(c)) quote = c;
        else if (c === '/' && n === '/') { comment = 'line'; i++; }
        else if (c === '/' && n === '*') { comment = 'block'; i++; }
        else if (c === '{') depth++;
        else if (c === '}' && --depth === 0) return text.slice(first, i + 1);
    }
    throw new Error(`Unclosed source body ${marker}`);
}
