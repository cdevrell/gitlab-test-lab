if (!$env:GITLAB_HOSTNAME) {
    $env:GITLAB_HOSTNAME = Read-Host "Enter Gitlab hostname"
}

if (!(Test-Path gitlab-server/.env)) {
    Set-Content -Value "GITLAB_HOSTNAME=$env:GITLAB_HOSTNAME" -Path gitlab-server/.env
}

Write-Host "Starting Gitlab...."
docker-compose -f gitlab-server/docker-compose.yaml up -d

Write-Host "Waiting for Gitlab to become available..."
$response = $null
$attempt = 1
do {
    try {
        $response = Invoke-WebRequest -Uri http://$env:GITLAB_HOSTNAME/-/readiness -SkipHttpErrorCheck
    }
    catch {
        Start-Sleep 10
        $attempt++
    }
} while (
    $response.StatusCode -ne 200
)
## If Gitlab responds ready after first attempt, it must have been started previsouly so skip the extra long wait
if ($attempt -gt 1) {
    Write-Host "Almost ready..."
    Start-Sleep 30
}
Write-Host "Gitlab is running..."

## Set token and headers and do a login check in case script has been run previously.
$patToken = "glpat-RootUserToken1234!!!"
$header = @{
    "PRIVATE-TOKEN" = $patToken
}
$patCheck = Invoke-WebRequest -Uri "http://$env:GITLAB_HOSTNAME/api/v4/version" -Headers $header -SkipHttpErrorCheck

if ($patCheck.StatusCode -ne 200) {
    Write-Host "Creating Personal Access Token for 'root' user..."
    docker exec gitlab gitlab-rails runner "token = User.find_by_username('root').personal_access_tokens.create(scopes: ['api'], name: 'Root Token', expires_at: 365.days.from_now); token.set_token('$($patToken)'); token.save!"
}

## Create GitLab Runner
### Check if Runner already exists
$runnerName = "K8s Runners"
$runners = (Invoke-WebRequest -Uri "http://$env:GITLAB_HOSTNAME/api/v4/runners/all" -Headers $header).Content | ConvertFrom-Json
$runnerExists = $false
foreach ($runner in $runners) {
    if ($runner.description -eq $runnerName) {
        $runnerExists = $true
        break
    }
}

## Create Runner and store registration token
if (!$runnerExists) {
    Write-Host "Creating Gitlab Runner..."
    $runnerData = @{
        description  = $runnerName
        tag_list     = "local"
        run_untagged = $true
        runner_type  = "instance_type"
    }

    $newRunnerResponse = Invoke-WebRequest `
        -Uri http://$env:GITLAB_HOSTNAME/api/v4/user/runners `
        -Method Post `
        -Headers $header `
        -Form $runnerData
  
    $registrationToken = ($newRunnerResponse.Content | ConvertFrom-Json).token
    
    ## Deploy Runner Helm Chart to Kubernetes
    Write-Host "Deploying Gitlab Runner to Kubernetes..."
    helm repo add gitlab https://charts.gitlab.io
    helm upgrade gitlab-runner `
        --install `
        --set gitlabUrl="http://$env:GITLAB_HOSTNAME" `
        --set runnerRegistrationToken=$registrationToken `
        --set rbac.create=true `
        --set serviceAccount.create=true `
        gitlab/gitlab-runner

}

$existingGroups = (Invoke-WebRequest -Uri "http://$env:GITLAB_HOSTNAME/api/v4/groups" -Headers $header).Content | ConvertFrom-Json

## Create DEV Parent Group
foreach ($g in $existingGroups) {
    if ($g.name -eq "DEV") {
        $devGroupId = $g.id
        Write-Host "Group 'DEV' already exists"
        break
    }
}
if (!$devGroupId ) {
    Write-Host "Creating 'DEV' Group..."
    $devGroupData = @{
        name = "DEV"
        path = "dev"
    }
    $createDevGroupResponse = Invoke-WebRequest `
        -Uri http://$env:GITLAB_HOSTNAME/api/v4/groups `
        -Method Post `
        -Headers $header `
        -Form $devGroupData
    $devGroupId = ($createDevGroupResponse.Content | ConvertFrom-Json).id
}


## Create groups and repos
$repos = @("application/hello-world", "environment/deployment", "environment/infrastructure", "terraform-modules/s3")
foreach ($repo in $repos) {
    $existingGroups = (Invoke-WebRequest -Uri "http://$env:GITLAB_HOSTNAME/api/v4/groups" -Headers $header).Content | ConvertFrom-Json
    $existingProjects = (Invoke-WebRequest -Uri "http://$env:GITLAB_HOSTNAME/api/v4/projects" -Headers $header).Content | ConvertFrom-Json
    $groupId = $null

    $groupName = $repo.Split("/")[0]
    $projectName = $repo.Split("/")[1]

    ## Check if group exists
    foreach ($g in $existingGroups) {
        if ($g.full_path -eq "dev/$groupName") {
            $groupId = $g.id
            Write-Host "Group dev/$groupName already exists"
            break
        }
    }

    if (!$groupId) {
        Write-Host "Creating 'dev/$groupName' Group..."
        $groupData = @{
            name      = $groupName
            path      = $groupName.ToLower()
            parent_id = $devGroupId
        }

        $createGroupResponse = Invoke-WebRequest `
            -Uri http://$env:GITLAB_HOSTNAME/api/v4/groups `
            -Method Post `
            -Headers $header `
            -Form $groupData
        
        $groupId = ($createGroupResponse.Content | ConvertFrom-Json).id
    }
    

    ## Check if project exists
    $projectExists = $false
    foreach ($p in $existingProjects) {
        if ($p.path_with_namespace -eq "dev/$repo") {
            Write-Host "Project dev/$repo already exists"
            $projectExists = $true
            break
        }
    }
    if (!$projectExists) {
        Write-Host "Creating 'dev/$repo' project..."
        $projectData = @{
            name         = $projectName
            namespace_id = $groupId
        }
        $createProjectResponse = Invoke-WebRequest `
            -Uri http://$env:GITLAB_HOSTNAME/api/v4/projects `
            -Method Post `
            -Headers $header `
            -Form $projectData
    
        Write-Host "Committing existing files..."
        $repoUrl = ($createProjectResponse.Content | ConvertFrom-Json).http_url_to_repo
        $repoUrlWithCreds = $repoUrl.replace("http://", "http://root:$patToken@")

        Push-Location "repos/$repo"
        if (Test-Path .git) {
            Remove-Item .git -Recurse -Force
        }
        git init --initial-branch=main
        git remote add origin $repoUrlWithCreds
        git add .
        git commit -m "Initial commit"
        git push --set-upstream origin main
        Pop-Location
    }
}


Write-Host "Deployment finsihed - Login to http://$env:GITLAB_HOSTNAME"