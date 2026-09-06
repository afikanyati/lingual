"""Repackage the pinned upstream ZIP as the deterministic tar.gz expected by Vosk WASM."""
import gzip
import io
import sys
import tarfile
import zipfile

with zipfile.ZipFile(sys.argv[1]) as source:
    with open(sys.argv[2], "wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as archive:
                for name in sorted(source.namelist()):
                    if name.endswith("/"):
                        continue
                    relative = name.split("/", 1)[1]
                    if ".." in relative.split("/") or relative.startswith("/"):
                        raise ValueError("Unsafe model archive path")
                    content = source.read(name)
                    entry = tarfile.TarInfo("model/" + relative)
                    entry.size = len(content)
                    entry.mode = 0o644
                    archive.addfile(entry, io.BytesIO(content))
