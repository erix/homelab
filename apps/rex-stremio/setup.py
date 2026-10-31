"""rex-stremio init: fetch a pinned static ffprobe into the PVC (once) and seed config.json (once).

ffprobe comes from the mwader/static-ffmpeg:9.0.2-1 linux/amd64 image layer, pulled straight from
Docker Hub by its content digest and verified, so no image build is needed. config.json is only
written when absent; after that the settings page (http://192.168.11.216:9982/) owns it.
"""
import hashlib, json, os, sys, tarfile, urllib.request

REPO = "mwader/static-ffmpeg"
LAYER = "sha256:0d86bdb699b112cbb34d970b18ab9bfa26b4114d18cda969fda2f6aa5d059d7d"
BIN = "/data/bin"
FFPROBE = os.path.join(BIN, "ffprobe")
MARKER = FFPROBE + ".layer"
CONFIG = "/data/config.json"
SEED = {
    "listen": "0.0.0.0:9982",
    "rex_url": "http://192.168.11.215:32400",
    "relay_url": "http://192.168.11.216:9982",
    "addons": [],
    "catalogs": [],
}


def ffprobe():
    if os.path.exists(FFPROBE) and os.path.exists(MARKER) and open(MARKER).read().strip() == LAYER:
        print("ffprobe present", flush=True)
        return
    os.makedirs(BIN, exist_ok=True)
    token = json.load(urllib.request.urlopen(
        "https://auth.docker.io/token?service=registry.docker.io&scope=repository:%s:pull" % REPO, timeout=60))["token"]
    request = urllib.request.Request("https://registry-1.docker.io/v2/%s/blobs/%s" % (REPO, LAYER),
                                     headers={"Authorization": "Bearer " + token})
    tmp = os.path.join(BIN, "layer.tar.gz.tmp")
    digest = hashlib.sha256()
    with urllib.request.urlopen(request, timeout=600) as response, open(tmp, "wb") as out:
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            digest.update(chunk)
            out.write(chunk)
    if "sha256:" + digest.hexdigest() != LAYER:
        os.remove(tmp)
        sys.exit("ffprobe layer digest mismatch")
    with tarfile.open(tmp, "r:gz") as tar:
        member = next(m for m in tar.getmembers() if m.name.lstrip("./") == "ffprobe" and m.isfile())
        with tar.extractfile(member) as src, open(FFPROBE + ".tmp", "wb") as dst:
            dst.write(src.read())
    os.chmod(FFPROBE + ".tmp", 0o755)
    os.replace(FFPROBE + ".tmp", FFPROBE)
    os.remove(tmp)
    with open(MARKER, "w") as handle:
        handle.write(LAYER + "\n")
    print("ffprobe installed", flush=True)


def config():
    if os.path.exists(CONFIG):
        print("config.json present, left as is", flush=True)
        return
    fd = os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(SEED, handle, indent=2)
    print("config.json seeded", flush=True)


ffprobe()
config()
