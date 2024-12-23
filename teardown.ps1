## Stop Gitlab
docker-compose -f gitlab-server/docker-compose.yaml down

## Delete files exposing hostname
$obfuscatedFiles = Get-ChildItem -Path *.tmp -Recurse -Force
foreach ($f in $obfuscatedFiles) {
    $newName = $f.FullName.Replace(".tmp","")
    if (Test-Path $newName) {
        Write-Host "Deleting $newName"
        Remove-Item $newName -force
    }
}

## Remove GitLab Runner
helm uninstall gitlab-runner

## Delete .git folders
Write-Host "Uninitializing local Git repos"
$repos = @("application/hello-world", "environment/deployment", "environment/infrastructure", "terraform-modules/s3")
foreach ($repo in $repos) {
    Push-Location "repos/$repo"
    if (Test-Path .git) {
        Remove-Item .git -Recurse -Force
    }
    Pop-Location
}