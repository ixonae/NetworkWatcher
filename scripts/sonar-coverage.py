"""Convert an xccov JSON archive from stdin to Sonar's generic coverage XML."""

import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


root = Path(__file__).resolve().parents[1]
source_dir = root / "NetworkWatcher"
coverage = ET.Element("coverage", version="1")

for filename, lines in sorted(json.load(sys.stdin).items()):
    path = Path(filename).resolve()
    if source_dir not in path.parents or path.suffix != ".swift":
        continue

    executable_lines = [line for line in lines if line["isExecutable"]]
    if not executable_lines:
        continue

    file_element = ET.SubElement(coverage, "file", path=path.relative_to(root).as_posix())
    for line in executable_lines:
        ET.SubElement(
            file_element,
            "lineToCover",
            lineNumber=str(line["line"]),
            covered="true" if line["executionCount"] > 0 else "false",
        )

if not len(coverage):
    sys.exit("No NetworkWatcher Swift coverage found in the Xcode archive.")

ET.ElementTree(coverage).write(sys.stdout.buffer, encoding="utf-8", xml_declaration=True)
