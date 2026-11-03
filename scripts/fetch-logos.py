#!/usr/bin/env python3
"""Banka ve aracı kurum logolarını kurumların kendi sitelerinden indirip yerel bir varlık kataloğuna yazar.

Logolar ilgili kurumların tescilli markalarıdır. Bu yüzden katalog
(BirikimDefteri/InstitutionLogos.xcassets) depoya eklenmez; yalnızca bu Mac'teki derlemelere girer.
Sitesinde 96 pikselden büyük simge bulunamayan kurumlarda, geliştiricisi o kurum olan App Store uygulamasının
simgesi kullanılır. Hiçbiri bulunamazsa kurum uygulamada kendi renginde baş harf rozetiyle görünür.

Kurum listesi ve adresler BirikimDefteri/Core/Institutions.swift dosyasından okunur.

Kullanım:
    python3 -I scripts/fetch-logos.py            # hepsi
    python3 -I scripts/fetch-logos.py ing midas  # yalnızca verilen kimlikler
"""

import gzip
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, urljoin

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "BirikimDefteri" / "Core" / "Institutions.swift"
NORMALIZER = ROOT / "scripts" / "normalize-logo.swift"
CATALOG = ROOT / "BirikimDefteri" / "InstitutionLogos.xcassets"
USER_AGENT = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
)
# Bu boyuttan küçük simgeler, daha büyüğü bulunamazsa kullanılır.
PREFERRED_SIZE = 96
MIN_SIZE = 48
WELL_KNOWN = ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png", "/apple-touch-icon-180x180.png"]


def institutions():
    """(kimlik, ad, renk, adres, takma adlar) listesi."""
    pattern = re.compile(
        r'Institution\(id: "([^"]+)", name: "([^"]+)", color: 0x([0-9A-Fa-f]{6}),.*?domain: "([^"]+)", aliases: \[([^\]]*)\]\)'
    )
    return [(*match.groups()[:4], re.findall(r'"([^"]+)"', match.group(5)))
            for match in pattern.finditer(SOURCE.read_text(encoding="utf-8"))]


def tokens(text):
    """Institution.normalizedTokens ile aynı: Türkçe küçük harf, aksansız, kelimelere bölünmüş."""
    text = text.replace("I", "ı").replace("İ", "i").lower().replace("ı", "i")
    text = "".join(char for char in unicodedata.normalize("NFKD", text) if not unicodedata.combining(char))
    return re.findall(r"[^\W_]+", text)


def match(text, entries):
    """Institution.match ile aynı: en uzun ardışık takma ad eşleşmesinin kurum kimliği."""
    words = tokens(text)
    best, length = None, 0
    for identifier, _, _, _, aliases in entries:
        for alias in map(tokens, aliases):
            if len(alias) > length and any(words[i:i + len(alias)] == alias for i in range(len(words) - len(alias) + 1)):
                best, length = identifier, len(alias)
    return best


def download(url, target):
    """URL'yi dosyaya indirir; (son adres, içerik türü) döner, olmazsa None."""
    result = subprocess.run(
        ["curl", "-sSL", "--compressed", "--max-time", "15", "--max-filesize", "3000000", "-A", USER_AGENT,
         "-o", str(target), "-w", "%{http_code} %{url_effective} %{content_type}", url],
        capture_output=True, text=True,
    )
    parts = result.stdout.split(" ", 2)
    if result.returncode != 0 or len(parts) < 2 or not parts[0].startswith("2"):
        return None
    data = target.read_bytes()
    if data[:2] == b"\x1f\x8b":
        # Bazı sunucular dosyayı başlık bildirmeden gzip'li gönderiyor.
        try:
            target.write_bytes(gzip.decompress(data))
        except OSError:
            return None
    return parts[1], parts[2] if len(parts) > 2 else ""


class IconLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.icons = []
        self.manifests = []

    def handle_starttag(self, tag, attrs):
        if tag != "link":
            return
        attrs = {key: value or "" for key, value in attrs}
        rel = attrs.get("rel", "").lower()
        href = attrs.get("href", "")
        if not href:
            return
        if "manifest" in rel:
            self.manifests.append(href)
        elif "icon" in rel and "mask-icon" not in rel:
            self.icons.append((rel, href, attrs.get("sizes", ""), attrs.get("type", "")))


def largest(sizes, default):
    values = [int(width) for width, _ in re.findall(r"(\d+)x(\d+)", sizes)]
    return max(values) if values else default


def is_vector(href, kind):
    return href.lower().split("?")[0].endswith(".svg") or "svg" in kind


def candidates(domain, workdir):
    """En uygundan başlayarak denenecek görsel adresleri."""
    found = []
    for base in (f"https://www.{domain}/", f"https://{domain}/"):
        page = workdir / f"page-{len(found)}.html"
        loaded = download(base, page)
        if not loaded:
            continue
        final_url = loaded[0]
        parser = IconLinks()
        parser.feed(page.read_text(encoding="utf-8", errors="ignore"))

        for rel, href, sizes, kind in parser.icons:
            if is_vector(href, kind):
                continue
            priority = 0 if "apple-touch-icon" in rel else 2
            default = 180 if priority == 0 else 32
            found.append((priority, -largest(sizes, default), urljoin(final_url, href)))

        for href in parser.manifests:
            manifest_url = urljoin(final_url, href)
            manifest = workdir / "manifest.json"
            if not download(manifest_url, manifest):
                continue
            try:
                icons = json.loads(manifest.read_text(encoding="utf-8", errors="ignore")).get("icons", [])
            except (ValueError, AttributeError):
                continue
            for icon in icons:
                src = icon.get("src", "")
                if src and not is_vector(src, icon.get("type", "")):
                    found.append((1, -largest(icon.get("sizes", ""), 0), urljoin(manifest_url, src)))

        for path in WELL_KNOWN:
            found.append((3, 0, urljoin(final_url, path)))

    seen = set()
    for _, _, url in sorted(found):
        if url not in seen:
            seen.add(url)
            yield url


def normalized_png(raw, workdir, normalizer, color):
    """Görseli 192×192 PNG'ye çevirir; (png, en büyük kenar) döner."""
    png = workdir / "logo.png"
    result = subprocess.run([str(normalizer), str(raw), str(png), color], capture_output=True, text=True)
    sizes = result.stdout.split()
    if result.returncode != 0 or len(sizes) != 2:
        return None
    return png, max(map(int, sizes))


def app_store_icon(identifier, name, color, entries, workdir, normalizer):
    """Kurumun App Store'daki uygulamasının simgesi; (png, kenar, adres) ya da None.

    Geliştiricisi bu kurum olan uygulamalar ya da adı bu kurumu anan ve listedeki bir kurumca geliştirilen
    uygulamalar kabul edilir (ör. Aktif Bank'ın N Kolay'ı). Birden çoksa ana uygulama seçilir: adı kurumu anan,
    "Mobil" ya da "Cep" geçen ya da adı kurumun adıyla aynı olan; eşitlikte en çok değerlendirilen.
    """
    results = workdir / "appstore.json"
    url = f"https://itunes.apple.com/search?term={quote(name)}&country=tr&entity=software&limit=15"
    if not download(url, results):
        return None
    try:
        apps = json.loads(results.read_text(encoding="utf-8")).get("results", [])
    except ValueError:
        return None

    def belongs(app):
        if "6015" not in map(str, app.get("genreIds", [])):  # yalnızca Finans kategorisi
            return False
        developer = match(app.get("artistName", "") + " " + app.get("sellerName", ""), entries)
        return developer == identifier or (developer is not None and match(app.get("trackName", ""), entries) == identifier)

    def rank(app):
        words = tokens(app.get("trackName", ""))
        names_it = match(app.get("trackName", ""), entries) == identifier
        is_main = words == tokens(name) or any(word.startswith("mobil") or word in ("mobile", "cep") for word in words)
        return names_it + is_main, app.get("userRatingCount", 0)

    apps = sorted((app for app in apps if app.get("artworkUrl512") and belongs(app)), key=rank, reverse=True)
    for app in apps[:3]:
        attempt = Path(tempfile.mkdtemp(dir=workdir))
        if download(app["artworkUrl512"], attempt / "raw") and (normalized := normalized_png(attempt / "raw", attempt, normalizer, color)):
            return (*normalized, f"App Store: {app.get('trackName')} ({app.get('artistName')})")
    return None


def write_imageset(identifier, png):
    imageset = CATALOG / f"inst-{identifier}.imageset"
    shutil.rmtree(imageset, ignore_errors=True)
    imageset.mkdir(parents=True)
    shutil.copy(png, imageset / "logo.png")
    contents = {"images": [{"filename": "logo.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def main():
    wanted = set(sys.argv[1:])
    known = institutions()
    entries = [entry for entry in known if not wanted or entry[0] in wanted]
    CATALOG.mkdir(exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")

    staging = Path(tempfile.mkdtemp(prefix="birikim-logos-"))
    missing = []
    try:
        normalizer = staging / "normalize-logo"
        subprocess.run(["xcrun", "swiftc", "-O", str(NORMALIZER), "-o", str(normalizer)], check=True)
        for identifier, name, color, domain, _ in entries:
            workdir = Path(tempfile.mkdtemp(dir=staging))
            best = None
            for index, url in enumerate(candidates(domain, workdir)):
                attempt = Path(tempfile.mkdtemp(dir=workdir))
                normalized = download(url, attempt / "raw") and normalized_png(attempt / "raw", attempt, normalizer, color)
                if normalized and normalized[1] >= MIN_SIZE and (best is None or normalized[1] > best[1]):
                    best = (*normalized, url)
                if (best and best[1] >= PREFERRED_SIZE) or index >= 12:
                    break
            if not best or best[1] < PREFERRED_SIZE:
                best = app_store_icon(identifier, name, color, known, workdir, normalizer) or best
            if best:
                write_imageset(identifier, best[0])
                print(f"✓ {name}: {best[1]} px · {best[2]}")
            else:
                missing.append(name)
                print(f"✗ {name}: uygun logo bulunamadı ({domain})")
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    print(f"\n{len(entries) - len(missing)} / {len(entries)} logo hazır.")
    if missing:
        print("Bulunamayanlar baş harf rozetiyle görünür: " + ", ".join(missing))


if __name__ == "__main__":
    main()
