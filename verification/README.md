# Learn Python through Azure deployment verification

This is a manually triggered, read-only check of your deployed automation. It does not start runbooks, change SKUs, or test application HTTP endpoints. It checks the identity configuration, published runbooks, metric rules, and Action Group receiver references. It does not prove runtime RBAC, webhook delivery, or successful scaling.

## Install and run in GitHub

1. Copy the `verification/` directory into the repository root.
2. Copy `.github/workflows/verify-deployment.yml` into the existing workflows directory. Some file browsers hide `.github`; enable hidden files to see it.
3. Open `verification/expected.json`. Confirm the resource group, Automation Account, two plan names, plan resource groups, runbook names, alert thresholds, and Action Group names match your intended deployment.
4. Confirm the GitHub Environment `POC` has `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, and `ARM_SUBSCRIPTION_ID` secrets. These belong to your GitHub deployment service principal, not the Automation Account identity. This suite only needs read access to the listed resources; do not grant extra Contributor permissions for these tests.
5. Commit these files and merge the workflow into your default branch, `prod`.
6. Open Actions → Verify Azure deployment → Run workflow. Select `prod`. Approve the environment job if your environment requires it.
7. Read the Run Python verification logs. Download `azure-verification-results` from the workflow artifacts to obtain the JUnit XML report.

The workflow builds the image locally on its runner. It does not push to a container registry. Credentials are injected only when the container runs. The Docker build context includes only the verification files.

## What each file does

| File | Responsibility |
| --- | --- |
| `expected.json` | Defines the resources and settings we expect |
| `conftest.py` | Creates shared authentication and Azure clients |
| `test_deployment.py` | Compares real Azure configuration with expectations |
| `requirements.txt` | Pins the installed Python dependency versions |
| `Dockerfile` | Packages Python and the tests |
| `.dockerignore` | Allows only required files into the build context |
| `verify-deployment.yml` | Builds the image, runs tests, uploads the report |

## Lesson 1: A test is a question with an expected answer

Start with this function from `test_deployment.py`:

```python
@pytest.mark.parametrize("name", CONFIG["runbooks"])
def test_runbook_is_published(automation, name):
    runbook = automation.runbook.get(RG, ACCOUNT, name)
    assert runbook.properties is not None, f"Runbook {name} has no properties"
    assert runbook.properties.state == "Published", f"Runbook {name} is not published"
```

- `def` defines a function: a named block of instructions.
- pytest discovers functions whose names start with `test_`.
- `automation` is the Azure client supplied by a fixture in `conftest.py`.
- `name` is one runbook name supplied by `parametrize`.
- `.get(...)` asks Azure for the existing runbook. It does not create or start one.
- `runbook = ...` stores the response in a variable.
- `.properties.state` reads a field within that response. This matches the pinned Automation SDK version.
- `assert` means “this condition must be true.” If it is false, pytest marks the test as failed.
- `==` compares two values; `=` assigns a value to a variable.
- `f"Runbook {name} ..."` inserts the variable's value into the error message.
- Indentation marks the instructions belonging to the function. Use four spaces.

`parametrize` runs this function three times, once for each configured runbook. The result is three separate pass/fail entries instead of one loop that stops at the first failure.

## Lesson 2: Configuration and dictionaries

```python
CONFIG = json.loads(Path(__file__).with_name("expected.json").read_text())
RG = CONFIG["resource_group"]
```

`Path(__file__)` refers to the current Python file. `with_name(...)` selects the JSON file in the same directory. `read_text()` reads it, and `json.loads()` turns the text into Python dictionaries and lists.

A dictionary stores named values. `CONFIG["resource_group"]` retrieves the value under that key. A list stores several items, such as the three runbook names.

## Lesson 3: Fixtures and authentication

```python
@pytest.fixture(scope="session")
def automation(credential, subscription_id):
    with AutomationClient(credential, subscription_id) as client:
        yield client
```

A fixture supplies something a test needs. pytest matches the argument name `automation` in your test to the fixture function named `automation`.

`scope="session"` means create the client once for this test run. `yield` hands it to the tests. The `with` block closes the client afterward.

`EnvironmentCredential` reads `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `AZURE_TENANT_ID`. The workflow maps your existing GitHub secrets to these names. The subscription ID selects the resources the client queries. A host Azure CLI login is not required inside this container.

## Lesson 4: Repeating checks without repeating code

There are two plans and four alert definitions. The list comprehension named `ALERT_CASES` builds their eight combinations. `parametrize` then runs `test_metric_alert` for each combination.

The test checks scope, enabled state, threshold, metric name, operator, aggregation, evaluation frequency, evaluation window, and the destination Action Group. The final two tests inspect each group's runbook receiver.

Expected total: **14 tests** (1 identity + 3 runbooks + 8 alerts + 2 routing checks).

## Lesson 5: Docker and the workflow

The Dockerfile installs dependencies, copies the test files, and runs pytest. Its command includes `--junitxml=/results/results.xml` to write a report.

The workflow mounts a runner directory at `/results`. That preserves the report after the container exits. `--user` runs the container with the runner's user ID so the report is accessible. `-e NAME` passes an environment variable by name without putting its secret value in the command.

A failing pytest exit code makes `docker run` fail, which makes the workflow step fail. The upload step uses `if: always()` so a report is uploaded even when tests fail, if the report exists. The workflow has a 15-minute timeout.

## Interpret failures

| Result | Meaning |
| --- | --- |
| `PASSED` | The check matched its expectation |
| Assertion failure | Azure returned a resource, but a checked setting differed |
| HTTP 404 | Resource name/scope may be wrong, or the resource is missing |
| HTTP 403 | The test identity cannot read the requested resource |
| Missing environment variables | Required GitHub secrets were not passed to the container |
| Docker build failure | Tests did not run; inspect the dependency/build error |

Do not change expectations merely to make a failed test green. First decide whether Azure or the intended configuration is wrong. Do not print full Action Group objects: receiver URLs may contain webhook secrets.

## First learning exercise

After one successful run, change one expected runbook name to `does-not-exist` and run the workflow on a trusted branch. That should fail without changing Azure. Restore the correct name afterward. This demonstrates that the test detects a missing resource.

## Validation performed while preparing these files

Dependencies installed and all 14 tests collected locally. SDK field and client names were inspected against the installed versions. No Azure credentials were available, so the live checks were not executed. Docker was unavailable locally, so the image build awaits the GitHub run.
