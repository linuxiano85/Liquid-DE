.pragma library

function canPrint(path) {
    return typeof path === "string" && /\.(pdf|png|jpe?g|tiff?|bmp|webp|txt)$/i.test(path);
}
