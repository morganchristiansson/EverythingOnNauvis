################################################################################
#
# Creates zip file for mod
#
################################################################################

import glob
import os
import re
import zipfile
from typing import List

MOD_NAME = "EverythingOnNauvis-morganc"
PATH = os.getcwd()
INFO_JSON_PATH = fr"{PATH}\info.json"
INFO_JSON_VERSION_REGEX = r"\"version\": \"([A-Za-z0-9]+(\.[A-Za-z0-9]+)+)\""
TARGET_PATH = fr"D:\Factorio modding\{MOD_NAME} versions"

IMAGE_REGEX = r"\"([^\"]*.png)\"([^\n]*)"
SKIP_IMAGE_FLAG = r"#SKIP IMAGE#"


PATHS_TO_SKIP = [".git",
                 ".pytest_cache",
                 ".vscode",
                 "tests",
                 "python",
                 "screenshots",
                 ".editorconfig",
                 ".gitignore"]


def get_version_from_info_json() -> str:
    """
    Gets the current version from json.info

    @return: version as string
    """
    info_json_file = open(INFO_JSON_PATH, mode = 'r')
    info_json_text = info_json_file.read()
    version = re.search(INFO_JSON_VERSION_REGEX, info_json_text).group(1)
    return version


def create_zip():
    """
    Creates zip
    """
    zip_path = fr"{TARGET_PATH}\{MOD_NAME}_{get_version_from_info_json()}.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        # Add all files except the ones listed in PATHS_TO_SKIP
        for root, dirs, files in os.walk(PATH):
            for file in files:
                relative_path = os.path.join(root, file).replace(f"{PATH}\\", "")
                if relative_path.split("\\")[0] not in PATHS_TO_SKIP:
                    z.write(os.path.join(root, file), fr"{MOD_NAME}\{relative_path}")


if __name__ == "__main__":
    create_zip()
