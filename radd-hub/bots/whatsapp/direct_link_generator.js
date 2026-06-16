/**
 * Pure JavaScript (Node.js) method to generate a direct download/streaming link
 * from a JazzDrive folder share URL.
 *
 * FIXED: The k= signed token in the video URL is self-authenticating.
 *        Do NOT append validationkey= — it is not needed and breaks the URL.
 *        Poster is extracted from the thumbnails[] array (zero-rated JD image).
 *
 * Requirements: 'node-fetch' (already in your project)
 */

const fetch = require('node-fetch');

const CLOUD = 'https://cloud.jazzdrive.com.pk';

/**
 * Generates a direct download + poster link from a JazzDrive share URL.
 *
 * @param {string} shareUrl        - The folder share URL (e.g., https://cloud.jazzdrive.com.pk/share/f/...)
 * @param {string} targetFilename  - Optional: substring of the filename to match if multiple files exist.
 * @returns {Promise<{success, filename, directLink, posterUrl, sizeBytes, validationKey?, error?}>}
 */
async function generateDirectLink(shareUrl, targetFilename = "") {
    // 1. Extract Share Key from URL
    const shareKey = shareUrl.match(/\/(?:share-landing\/f|share\/f|f)\/([^\/?#]+)/)?.[1];
    if (!shareKey) {
        return { success: false, error: "Invalid JazzDrive share URL format." };
    }

    const baseHeaders = {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json;charset=UTF-8',
        'Origin': CLOUD,
        'Referer': `${CLOUD}/share/f/${shareKey}`,
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'X-Requested-With': 'com.jazz.drive',
    };

    try {
        // 2. Login — get validationkey + JSESSIONID for the share session
        const loginResp = await fetch(`${CLOUD}/sapi/link/login?action=login`, {
            method: 'POST',
            headers: baseHeaders,
            body: JSON.stringify({ data: { accesstoken: shareKey } }),
        });

        if (!loginResp.ok) {
            return { success: false, error: `Login failed: HTTP ${loginResp.status}` };
        }

        const loginData = await loginResp.json();
        const vk = loginData?.data?.validationkey || loginData?.validationkey;
        if (!vk) {
            return { success: false, error: "No validation key returned from JazzDrive login." };
        }

        // Extract JSESSIONID cookie (needed for the media list request)
        const setCookie = loginResp.headers.get('set-cookie') || '';
        const jsessionid = (setCookie.match(/JSESSIONID=([^;]+)/) || [])[1] || '';
        const cookieHeader = jsessionid ? `JSESSIONID=${jsessionid}` : '';

        // 3. Fetch the video list for this share
        const mediaUrl = `${CLOUD}/sapi/media/video?action=get&shared=true&key=${shareKey}&validationkey=${encodeURIComponent(vk)}`;
        const mediaResp = await fetch(mediaUrl, {
            headers: {
                ...baseHeaders,
                Cookie: cookieHeader,
            },
        });

        if (!mediaResp.ok) {
            return { success: false, error: `Media fetch failed: HTTP ${mediaResp.status}` };
        }

        const mediaData = await mediaResp.json();
        const res = mediaData?.data || mediaData;
        let records = [];
        if (Array.isArray(res)) records = res;
        else if (res && typeof res === 'object') {
            records = res.videos || res.items || res.list || res.result || [];
        }

        if (!records.length) {
            return { success: false, error: "No video files found in this share." };
        }

        // 4. Pick best match (by filename substring, or first record)
        const tf = (targetFilename || "").toLowerCase();
        const record = (tf
            ? records.find(r => ((r.name || r.filename || "")).toLowerCase().includes(tf))
            : null) || records[0];

        // 5. Build final download URL
        //    The url field = /sapi/download/video?action=get&k=<SIGNED>&node=<NODE>
        //    The k= token IS the auth — it is pre-signed. Do NOT add validationkey.
        let rawUrl = record.url || record.downloadUrl || record.download_url || "";
        if (!rawUrl) {
            return { success: false, error: "No URL found in video record." };
        }
        if (rawUrl.startsWith('/')) rawUrl = CLOUD + rawUrl;

        // Use real filename from the server (correct extension, e.g. .mkv not .mp4)
        const name = record.name || record.filename || "video.mkv";
        const sep = rawUrl.includes('?') ? '&' : '?';
        const directLink = rawUrl.includes('filename=')
            ? rawUrl
            : `${rawUrl}${sep}filename=${encodeURIComponent(name)}`;

        // 6. Extract poster from thumbnails[] (zero-rated JazzDrive-hosted image)
        const thumbnails = record.thumbnails || [];
        let posterUrl = "";
        if (thumbnails.length > 0) {
            let turl = thumbnails[thumbnails.length - 1]?.url || thumbnails[0]?.url || "";
            if (turl.startsWith('/')) turl = CLOUD + turl;
            posterUrl = turl;
        }

        return {
            success:      true,
            filename:     name,
            directLink:   directLink,
            posterUrl:    posterUrl,
            sizeBytes:    record.size || record.filesize || 0,
            validationKey: vk,
        };

    } catch (err) {
        return { success: false, error: err.message };
    }
}


// --- TEST BLOCK ---
if (require.main === module) {
    const testUrl  = 'https://cloud.jazzdrive.com.pk/share/f/lTzy2wdJQDqnsHSZNJGMBjA0NzE3MTIzNzE2NzFfMjYwMzgwMA';
    const testFile = 'Interstellar';

    generateDirectLink(testUrl, testFile).then(result => {
        if (result.success) {
            console.log("--- SUCCESS ---");
            console.log("File:     ", result.filename);
            console.log("Direct:   ", result.directLink.slice(0, 120) + "...");
            console.log("Poster:   ", result.posterUrl.slice(0, 80) + "...");
            console.log("Size:     ", Math.round(result.sizeBytes / 1024 / 1024) + " MB");
        } else {
            console.log("--- FAILED ---");
            console.log("Error:", result.error);
        }
    });
}

module.exports = { generateDirectLink };
