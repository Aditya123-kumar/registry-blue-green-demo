
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
                    $image = "localhost:5000/flask-python-app:$tag"

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
                        $image = "localhost:5000/flask-python-app:$tag"

                        $env:REGISTRY_PASSWORD | docker login 127.0.0.1:5000 --username $env:REGISTRY_USER --password-stdin
                        if ($LASTEXITCODE -ne 0) {
                            throw "Registry login failed"
                        }

                        docker push $image
                        if ($LASTEXITCODE -ne 0) {
                            throw "Image push failed"
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
                    $image = "localhost:5000/flask-python-app:$tag"
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

                        $switched = $true

                        docker exec flask-proxy nginx -t
                        if ($LASTEXITCODE -ne 0) {
                            throw "Proxy configuration validation failed"
                        }

                        docker exec flask-proxy nginx -s reload
                        if ($LASTEXITCODE -ne 0) {
                            throw "Proxy reload failed"
                        }

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


