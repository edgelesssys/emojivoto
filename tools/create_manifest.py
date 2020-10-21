#!/usr/bin/env python3

import os
import argparse
import json
import re
import struct
import glob
import pathlib


def createManifest(manifestFile, configDir):
    manifest = {}
    with open(manifestFile, "r") as f:
        manifest = json.load(f)
    for path in glob.glob(os.path.join(configDir, "*.json")):
        config = {}
        name = os.path.splitext(os.path.basename(path))[0]
        with open(path, "r") as f:
            config = json.load(f)
        if name in manifest["Packages"]:
            pkg = manifest["Packages"][name]
            pkg["UniqueID"] = config["UniqueID"]
            pkg["SignerID"] = config["SignerID"]
            pkg["SecurityVersion"] = config["SecurityVersion"]
            pkg["ProductID"] = [config["ProductID"]]
            manifest["Packages"][name] = pkg

    return manifest
    
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-m', '--manifest', required=True)
    parser.add_argument('-c', '--configs', required=True)
    parser.add_argument('-o', '--output',  help="file to store configuration")
    args = parser.parse_args()
    
    manifest = createManifest(args.manifest, args.configs)
    if args.output:
        with open(args.output, "w") as f:
            json.dump(manifest, f, indent=4)
    else:
        print(json.dumps(manifest, indent=4))