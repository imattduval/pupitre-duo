#!/usr/bin/env python3
"""Classe les morceaux du compte par décennie et langue via MusicBrainz (1 requête par seconde).
Reprend là où il s'est arrêté grâce au cache. Usage : classer.py compte.json classement.json cache.json"""
import json, os, re, sys, time, unicodedata, urllib.parse, urllib.request

compte, sortie, cache_path = sys.argv[1:4]
# « export » : écrit le classement avec ce que le cache connaît déjà, sans réseau.
EXPORT = sys.argv[4:] == ["export"]
AGENT = "PupitreDuo/1.0 (https://github.com/imattduval/pupitre-duo)"
cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}

FR = {"le","la","les","un","une","des","du","de","je","tu","il","elle","nous","vous","on","mon","ma","mes","ton","ta","tes","et","ou","pour","dans","sur","que","qui","pas","plus","sans","toi","moi","cette","ce","au","aux","amour","vie","jour","nuit"}
EN = {"the","a","i","you","me","my","your","love","of","in","on","to","and","it","is","we","all","for","with","baby","dont","cant","im","no","one","time","night","up","down","man","girl","boy","be"}
FR_COUNTRIES = {"FR", "BE", "CH", "CA", "LU", "MC", "SN", "CI", "ML", "CM", "HT", "DZ", "MA", "TN"}
EN_COUNTRIES = {"GB", "US", "AU", "IE", "NZ", "JM", "ZA"}

def get(path):
    time.sleep(1.1)
    request = urllib.request.Request("https://musicbrainz.org/ws/2/" + path, headers={"User-Agent": AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                return json.load(response)
        except Exception:
            time.sleep(10 * (attempt + 1))
    return None

def clean(text):
    return re.sub(r'[+\-!(){}\[\]^"~*?:\\/&|]', " ", text).strip()

def lookup(title, artist):
    query = f'recording:({clean(title)}) AND artist:({clean(artist)})'
    data = get("recording?fmt=json&limit=15&query=" + urllib.parse.quote(query))
    if data is None:
        return None
    years, artist_id = [], None
    for item in data.get("recordings", []):
        if item.get("score", 0) < 85:
            continue
        credit = item.get("artist-credit") or []
        if credit and not artist_id:
            artist_id = credit[0]["artist"]["id"]
        match = re.match(r"(\d{4})", item.get("first-release-date", ""))
        if match and int(match.group(1)) >= 1900:
            years.append(int(match.group(1)))
    return {"year": min(years) if years else None, "artist": artist_id}

def country(artist_id):
    key = "artist:" + artist_id
    if EXPORT:
        return cache.get(key)
    if key not in cache:
        data = get("artist/" + artist_id + "?fmt=json")
        if data is None:
            return None
        cache[key] = data.get("country")
    return cache[key]

def language(title, land):
    plain = unicodedata.normalize("NFD", title.lower())
    accents = plain != title.lower()
    words = set(re.findall(r"[a-z]+", "".join(c for c in plain if not unicodedata.combining(c))))
    french, english = len(words & FR), len(words & EN)
    if english > french:
        return "Anglais"
    if french > english or (accents and land in FR_COUNTRIES):
        return "Français"
    if land in FR_COUNTRIES:
        return "Français"
    if land in EN_COUNTRIES:
        return "Anglais"
    return "Autres langues" if land or accents else None

data = json.load(open(compte, encoding="utf-8"))
result = {}
for index, song in enumerate(data["songs"]):
    key = str(song["id"])
    if EXPORT and key not in cache:
        title = re.sub(r"\s*\(ver \d+\)$", "", song["title"])
        result[key] = {"decade": None, "language": language(title, None)}
        continue
    if key not in cache:
        title = re.sub(r"\s*\(ver \d+\)$", "", song["title"])
        artist = re.split(r"\s+(?:feat\.?|&|and)\s+", song["artist"], flags=re.I)[0]
        found = lookup(title, artist)
        if found is None:
            print("réseau indisponible, on garde le cache", flush=True)
            break
        cache[key] = found
    found = cache[key]
    land = country(found["artist"]) if found.get("artist") else None
    title = re.sub(r"\s*\(ver \d+\)$", "", song["title"])
    result[key] = {"decade": found["year"] // 10 * 10 if found.get("year") else None, "language": language(title, land)}
    if index % 20 == 0 and not EXPORT:
        json.dump(cache, open(cache_path, "w"))
        print(index, flush=True)

if not EXPORT:
    json.dump(cache, open(cache_path, "w"))
json.dump(result, open(sortie, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print("fini", len(result), "sur", len(data["songs"]), flush=True)
