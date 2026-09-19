# Contributing

Run `tools/check-package.sh` before opening a pull request. Changes to model,
vLLM, B12X, NCCL or base-image pins must include the upstream URL, immutable
commit/digest, reason for change, four-rank switchless result, and regression
receipt. A switched-fabric result may be included for diagnosis, but it cannot
replace the switchless collective and model receipts. Do not promote B12X or
switchless status from component-only evidence.

Never commit site configuration, credentials, model data, Docker archives or
qualification receipts containing host details.
