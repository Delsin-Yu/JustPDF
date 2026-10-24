# Local signing materials

Put HarmonyOS `.p12`, `.cer`, and `.p7b` files here. This directory is gitignored except this README.

Do not commit keystores, certificates, profiles, or the DevEco-encrypted passwords in `build-profile.json5`. Those materials can sign a HAP as this app; they cannot log into a Huawei developer account, but they still must stay private.
