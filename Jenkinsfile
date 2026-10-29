pipeline {
    agent any

    environment {
        IMAGE_NAME = 'localhost:5000/flask-python-app'
        CONFIG_PATH = 'C:/Users/CEREBRENT PC/registry-rollback-demo/flask-proxy/default.conf'
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Checkout and Build') {
            steps {
                bat 'docker version'

                powershell '''
                    $ErrorActionPreference = 'Stop'
                    $tag = "build-$env:BUILD_NUMBER"
                    $image = "${env:IMAGE_NAME}:$tag"

                    docker build -t $image .\\flask-app
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker build failed"
                    }

                    docker run --rm $image python -c "from app import app; c=app.test_client(); r=c.get('/health'); assert r.status_code == 200; print(r.get_json())"
                    if ($LASTEXITCODE -ne 0) {
                        throw "Flask health test failed"
                    }

                    Write-Host "Built and tested image: $image"
                '''
            }
        }

        stage('Push to Private Registry') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'registry-creds',
                        usernameVariable: 'REGISTRY_USER',
                        passwordVariable: 'REGISTRY_PASSWORD'
                    )
                ]) {
                    powershell '''
                        $ErrorActionPreference = 'Stop'
                        $tag = "build-$env:BUILD_NUMBER"
                        $image = "${env:IMAGE_NAME}:$tag"

                        Write-Host "=== Jenkins identity ==="
                        whoami

                        Write-Host "=== Docker context ==="
                        docker context show
                        if ($LASTEXITCODE -ne 0) {
                            throw "Cannot read Docker context"
                        }

                        Write-Host "=== Docker environment ==="
                        Get-ChildItem Env: |
                            Where-Object {
                                $_.Name -match '^(DOCKER_HOST|DOCKER_CONTEXT|DOCKER_CONFIG|HTTP_PROXY|HTTPS_PROXY|NO_PROXY)$'
                            } |
                            ForEach-Object {
                                Write-Host "$($_.Name)=$($_.Value)"
                            }

                        Write-Host "=== Docker config paths ==="
                        Write-Host "USERPROFILE=$env:USERPROFILE"
                        Write-Host "HOME=$env:HOME"
                        Write-Host "DOCKER_CONFIG=$env:DOCKER_CONFIG"

                        Write-Host "=== Credential binding check ==="
                        Write-Host "Registry username present: $([bool]$env:REGISTRY_USER)"
                        Write-Host "Registry password present: $([bool]$env:REGISTRY_PASSWORD)"

                        if ([string]::IsNullOrWhiteSpace($env:REGISTRY_USER) -or
                            [string]::IsNullOrEmpty($env:REGISTRY_PASSWORD)) {
                            throw "Registry credentials are missing from Jenkins binding."
                        }

                        Write-Host "=== Docker executable ==="
                        (Get-Command docker).Source

                        docker version --format '{{.Client.Version}}'
                        if ($LASTEXITCODE -ne 0) {
                            throw "Cannot read Docker client version"
                        }

                        Write-Host "=== Registry HTTPS certificate test ==="
                        $status = curl.exe -sS -o NUL -w "%{http_code}" https://127.0.0.1:5000/v2/
                        if ($LASTEXITCODE -ne 0) {
                            throw "HTTPS connection/certificate verification failed for https://127.0.0.1:5000/v2/"
                        }

                        Write-Host "HTTPS status=$status"

                        if ($status -ne '401' -and $status -ne '200') {
                            throw "Unexpected registry HTTPS status: $status"
                        }
Write-Host "=== Docker registry protocol diagnostic ==="

curl.exe -k -sS -o NUL -w "HTTPS status: %{http_code}`n" `
    https://localhost:5000/v2/

curl.exe -sS -o NUL -w "HTTP status: %{http_code}`n" `
    http://localhost:5000/v2/

docker info | Select-String -Pattern "Proxy|Insecure Registries"

                        Write-Host "=== Docker registry login ==="
                        $env:REGISTRY_PASSWORD |
                            docker login localhost:5000 --username $env:REGISTRY_USER --password-stdin

                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker login failed. Credentials were not printed."
                        }

                        Write-Host "=== Push image ==="
                        docker push $image
                        if ($LASTEXITCODE -ne 0) {
                            throw "Image push failed: $image"
                        }

                        Write-Host "Pushed image: $image"
                    '''
                }
            }
        }

        stage('Deploy and Verify') {
            steps {
                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $configPath = $env:CONFIG_PATH
                    $tag = "build-$env:BUILD_NUMBER"
                    $image = "${env:IMAGE_NAME}:$tag"
                    $proxyUrl = "http://localhost:8083"
                    $switched = $false
                    $originalConfig = Get-Content $configPath -Raw

                    try {
                        if ($originalConfig -match 'proxy_pass\\s+http://host\\.docker\\.internal:(\\d+)') {
                            $activePort = $Matches[1]
                        } else {
                            throw "Cannot determine active Flask proxy port"
                        }

                        if ($activePort -eq '8111') {
                            $targetPort = '8112'
                            $container = 'flask-green'
                        } elseif ($activePort -eq '8112') {
                            $targetPort = '8111'
                            $container = 'flask-blue'
                        } else {
                            throw "Unexpected active port: $activePort. No deployment performed."
                        }

                        Write-Host "Current live port: $activePort"
                        Write-Host "Deploying $image to $container on port $targetPort"

                        docker pull $image
                        if ($LASTEXITCODE -ne 0) {
                            throw "Cannot pull image $image"
                        }

                        $existing = docker ps -a --format "{{.Names}}"
                        if ($LASTEXITCODE -ne 0) {
                            throw "Cannot list existing containers"
                        }

                        if ($existing -contains $container) {
                            docker rm -f $container
                            if ($LASTEXITCODE -ne 0) {
                                throw "Cannot remove old inactive container"
                            }
                        }

                        docker run -d --restart unless-stopped --name $container -p "${targetPort}:5000" -e "APP_VERSION=$tag" $image
                        if ($LASTEXITCODE -ne 0) {
                            throw "Container startup failed"
                        }

                        $healthy = $false
                        for ($i = 1; $i -le 15; $i++) {
                            try {
                                $result = Invoke-RestMethod "http://localhost:$targetPort/health" -TimeoutSec 3
                                if ($result.status -eq 'healthy' -and $result.version -eq $tag) {
                                    $healthy = $true
                                    break
                                }
                            } catch {
                                Start-Sleep -Seconds 2
                            }

                            Start-Sleep -Seconds 1
                        }

                        if (-not $healthy) {
                            throw "New container failed health checks. Live traffic unchanged."
                        }

                        $newConfig = $originalConfig -replace 'host\\.docker\\.internal:\\d+', "host.docker.internal:$targetPort"
                        Set-Content -Path $configPath -Value $newConfig -Encoding ascii

                        docker exec flask-proxy nginx -t
                        if ($LASTEXITCODE -ne 0) {
                            Set-Content -Path $configPath -Value $originalConfig -Encoding ascii
                            throw "Proxy configuration validation failed; original config restored."
                        }

                        docker exec flask-proxy nginx -s reload
                        if ($LASTEXITCODE -ne 0) {
                            Set-Content -Path $configPath -Value $originalConfig -Encoding ascii
                            docker exec flask-proxy nginx -s reload
                            throw "Proxy reload failed; original config restored."
                        }

                        $switched = $true
                        $live = Invoke-RestMethod "$proxyUrl/health" -TimeoutSec 5

                        if ($live.status -ne 'healthy' -or $live.version -ne $tag) {
                            throw "Live proxy verification failed"
                        }

                        Write-Host "DEPLOYMENT SUCCESS"
                        Write-Host "Version: $tag"
                        Write-Host "Live color: $container"
                        Write-Host "Application URL: $proxyUrl"
                    } catch {
                        $failure = $_

                        if ($switched) {
                            Write-Host "Restoring previous proxy configuration..."
                            Set-Content -Path $configPath -Value $originalConfig -Encoding ascii
                            docker exec flask-proxy nginx -t

                            if ($LASTEXITCODE -eq 0) {
                                docker exec flask-proxy nginx -s reload
                            }
                        }

                        throw $failure
                    }
                '''
            }
        }
    }
}
