# ONE-COMMAND TEARDOWN OF ALL THREE STACKS IN THE CORRECT ORDER (PowerShell sibling of destroy_everything.sh).
# DESTROYS stream -> train -> data SO REMOTE-STATE DEPENDENCIES UNWIND CLEANLY.
# AFTER THIS RUNS SUCCESSFULLY, ZERO FRAUD-DETECTION RESOURCES REMAIN IN GCP.

$ErrorActionPreference = "Continue"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TfRoot   = Join-Path $RepoRoot "infra\terraform"

function Destroy-Stack {
    param(
        [string]$Name,
        [switch]$ContinueOnError
    )
    $StackDir = Join-Path $TfRoot $Name
    Write-Host "=== Destroying $Name stack ==="
    if (-not (Test-Path (Join-Path $StackDir ".terraform"))) {
        Write-Host "$Name stack never initialised - skipping"
        return
    }
    Push-Location $StackDir
    try {
        terraform destroy -auto-approve
        if ($LASTEXITCODE -ne 0 -and -not $ContinueOnError) {
            throw "$Name destroy failed with exit code $LASTEXITCODE"
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "$Name destroy reported issues - continuing"
        }
    } finally {
        Pop-Location
    }
}

Destroy-Stack -Name "stream" -ContinueOnError
Destroy-Stack -Name "train"  -ContinueOnError
Destroy-Stack -Name "data"

Write-Host ""
Write-Host "=== VERIFICATION ==="
Write-Host "If the next four commands print no fraud-detection resources, teardown succeeded."
Write-Host ""
Write-Host "VMs:"
gcloud compute instances list --filter="name~fraud"
Write-Host ""
Write-Host "Buckets:"
gcloud storage buckets list --filter="name~fraud-detection"
Write-Host ""
Write-Host "Artifact Registry repos:"
gcloud artifacts repositories list --filter="name~fraud-detection"
Write-Host ""
Write-Host "Pub/Sub topics:"
gcloud pubsub topics list --filter="name~fraud"
