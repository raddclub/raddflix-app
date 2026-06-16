'use strict';
const BANNED_WORDS = [
    'porn', 'sex', 'sexy', 'xxx', 'adult', 'nude', 'naked', 'erotic', 'blue movie',
    'xvideos', 'pornhub', 'brazzers', 'hot video', 'sunny leone', 'mia khalifa',
    'pussy', 'penis', 'dick', 'vagina', 'blowjob', 'cum', 'ejaculate', 'hardcore',
    'hentai', 'lust', 'orgasm', 'pleasure', 'stripper', 'topless', 'webcam',
    'onlyfans', 'xhamster', 'xnxx', 'chaturbate'
];
function isSafe(text) {
    if (!text) return true;
    const lower = text.toLowerCase();
    return !BANNED_WORDS.some(word => lower.includes(word));
}
function levenshtein(a, b) {
    if (a.length === 0) return b.length;
    if (b.length === 0) return a.length;
    const matrix = [];
    for (let i = 0; i <= b.length; i++) matrix[i] = [i];
    for (let j = 0; j <= a.length; j++) matrix[0][j] = j;
    for (let i = 1; i <= b.length; i++) {
        for (let j = 1; j <= a.length; j++) {
            if (b.charAt(i - 1) === a.charAt(j - 1)) {
                matrix[i][j] = matrix[i - 1][j - 1];
            } else {
                matrix[i][j] = Math.min(
                    matrix[i - 1][j - 1] + 1,
                    Math.min(matrix[i][j - 1] + 1, matrix[i - 1][j] + 1)
                );
            }
        }
    }
    return matrix[b.length][a.length];
}
function similarity(a, b) {
    const distance = levenshtein(a, b);
    return 1 - distance / Math.max(a.length, b.length);
}
function getSuggestions(query, titles, limit = 3) {
    const q = query.toLowerCase().trim();
    return titles
        .map(t => ({ title: t, score: similarity(q, t.toLowerCase()) }))
        .filter(s => s.score > 0.4) 
        .sort((a, b) => b.score - a.score)
        .slice(0, limit)
        .map(s => s.title);
}
module.exports = {
    isSafe,
    getSuggestions,
    BANNED_WORDS
};