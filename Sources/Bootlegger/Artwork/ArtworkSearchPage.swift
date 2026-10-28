import Foundation

/// Owns the web content used to collect image search results and display selections.
enum ArtworkSearchPage {
    static let collectorScript = """
        let previous = '';
        function collectImages() {
            const urls = Array.from(new Set(Array.from(document.images)
                .filter(image => image.naturalWidth >= 80 && image.naturalHeight >= 80)
                .map(image => image.currentSrc || image.src)
                .filter(url => /^(https:|data:image)/.test(url))));
            const signature = JSON.stringify(urls);
            if (signature === previous) return;
            previous = signature;
            window.webkit.messageHandlers.iconResults.postMessage({
                query: new URL(location.href).searchParams.get('q'), urls: urls
            });
        }
        let pending = null;
        function scheduleCollection() {
            clearTimeout(pending);
            pending = setTimeout(collectImages, 200);
        }
        new MutationObserver(scheduleCollection).observe(document.documentElement, {
            childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'srcset']
        });
        document.addEventListener('load', scheduleCollection, true);
        collectImages();
        """

    /// Keeps translated labels and remote URLs out of executable markup.
    static func html(searchingLabel: String) -> String {
        let labels = ["searching": searchingLabel]
        let labelsData = try! JSONSerialization.data(withJSONObject: labels)
        let labelsJSON = String(data: labelsData, encoding: .utf8)!
        return
            """
            <!doctype html><meta name="color-scheme" content="light dark">
            <style>
            body { font: 14px -apple-system; margin: 12px; }
            #grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
            button { padding: 6px; border: 1px solid #8886; border-radius: 8px;
                     background: #8881; cursor: pointer; height: 160px; }
            button:hover, button:focus { outline: 3px solid #0788ff; }
            img { width: 100%; height: 100%; object-fit: contain; }
            p { color: #888; line-height: 1.5; }
            </style><div id="grid"></div><p id="empty"></p>
            <script>
            const labels = \(labelsJSON);
            document.getElementById('empty').textContent = labels.searching;
            const displayed = new Set();
            window.addResults = function(urls) {
                for (const result of urls) {
                    const url = typeof result === 'string' ? result : result.url;
                    if (displayed.has(url)) continue;
                    displayed.add(url);
                    const button = document.createElement('button');
                    button.setAttribute('aria-label', result.label || '');
                    const image = document.createElement('img');
                    image.src = url;
                    image.loading = 'lazy';
                    button.appendChild(image);
                    button.onclick = () => window.webkit.messageHandlers.iconImage.postMessage(url);
                    document.getElementById('grid').appendChild(button);
                }
                document.getElementById('empty').hidden = displayed.size > 0;
            };
            </script>
            """
    }
}
