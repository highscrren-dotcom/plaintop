.pragma library

// ki18n's four functions on top of Qt's translator — one implementation for the window
// roots (where the shared QML finds a bare i18n()) and for the KI18nContext shim.
//
// The catalogs are the project's own po/ files converted by lconvert, and two facts about
// that conversion decide the calls below (both verified on Qt 6.10, docs/GOTCHAS.md):
// lconvert puts msgctxt into Qt's *disambiguation*, not into the context, so every lookup
// is qsTranslate("", text, context); and the plural forms survive only when lconvert was
// told the target language (-target-language ru), after which qsTranslate(…, n) picks the
// form by the language's own rule. ki18n substitutes %1…%9 itself; Qt leaves them, so
// the arguments are put in here — the first argument is %1, as ki18n has it, and for the
// plural calls the count is the first argument too.

function subst(text, args) {
    let out = String(text)
    for (let i = 0; i < args.length; i++)
        out = out.split("%" + (i + 1)).join(String(args[i]))
    return out
}

function tr(context, text) {
    // A missing translation comes back as the source: the same fallback ki18n has.
    return qsTranslate("", text, context || "")
}

function trn(context, singular, plural, n) {
    const got = qsTranslate("", singular, context || "", n)
    // Without a catalog Qt answers the singular whatever n is; English has two forms.
    if (got === singular && n !== 1) return plural
    return got
}

function i18n(text) {
    return subst(tr("", text), Array.prototype.slice.call(arguments, 1))
}

function i18nc(context, text) {
    return subst(tr(context, text), Array.prototype.slice.call(arguments, 2))
}

function i18np(singular, plural, n) {
    return subst(trn("", singular, plural, n), Array.prototype.slice.call(arguments, 2))
}

function i18ncp(context, singular, plural, n) {
    return subst(trn(context, singular, plural, n), Array.prototype.slice.call(arguments, 3))
}
