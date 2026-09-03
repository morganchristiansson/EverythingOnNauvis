################################################################################
#
# Creates zip file for mod
#
################################################################################

import os
import re
import zipfile

MOD_NAME = "EverythingOnNauvis-morganc"
PATH = os.getcwd()
INFO_JSON_PATH = os.path.join(PATH, "info.json")
INFO_JSON_VERSION_REGEX = r"\"version\": \"([A-Za-z0-9]+(\.[A-Za-z0-9]+)+)\""
# Output directory for the release zip (<repo>/versions, gitignored).
TARGET_PATH = os.path.join(PATH, "versions")

IMAGE_REGEX = r"\"([^\"]*.png)\"([^\n]*)"
SKIP_IMAGE_FLAG = r"#SKIP IMAGE#"


PATHS_TO_SKIP = [".git",
                 ".pytest_cache",
                 ".vscode",
                 "tests",
                 "python",
                 "screenshots",
                 ".editorconfig",
                 ".gitignore",
                 "versions",
                 "Dockerfile",
                 "docker-compose.yml"]


def get_version_from_info_json() -> str:
    """
    Gets the current version from json.info

    @return: version as string
    """
    with open(INFO_JSON_PATH, mode='r') as info_json_file:
        info_json_text = info_json_file.read()
    version = re.search(INFO_JSON_VERSION_REGEX, info_json_text).group(1)
    return version


def create_zip():
    """
    Creates zip
    """
    os.makedirs(TARGET_PATH, exist_ok=True)
    zip_path = os.path.join(TARGET_PATH, f"{MOD_NAME}_{get_version_from_info_json()}.zip")
    with zipfile.ZipFile(zip_path, "w") as z:
        # Add all files except the ones listed in PATHS_TO_SKIP
        for root, dirs, files in os.walk(PATH):
            # Don't descend into skipped top-level directories (e.g. .git)
            if os.path.abspath(root) == PATH:
                dirs[:] = [d for d in dirs if d not in PATHS_TO_SKIP]
            for file in files:
                full_path = os.path.join(root, file)
                relative_path = os.path.relpath(full_path, PATH)
                if relative_path.split(os.sep)[0] not in PATHS_TO_SKIP:
                    # Zip entries always use forward slashes, even on Windows
                    arcname = os.path.join(MOD_NAME, relative_path).replace(os.sep, "/")
                    z.write(full_path, arcname)
    print(f"Wrote {zip_path}")


if __name__ == "__main__":
    create_zip()
