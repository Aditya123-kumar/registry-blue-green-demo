
pipeline {
    agent any

    options {
        timestamps()
        skipDefaultCheckout(false)
    }

    environment {
        IMAGE_NAME = 'localhost:5000/flask-python-app'
    }

    stages {
        stage('Checkout and Build') {
            steps {
                echo 'Building application image...'

                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $image = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                    docker build -t $image .
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker build failed."
                    }

                    $container = "registry-ci-test-$env:BUILD_NUMBER"

                    try {
                        docker run -d --name $container -p 127.0.0.1:18181:80 $image
                        if ($LASTEXITCODE -ne 0) {
                            throw "Temporary container failed to start."
                        }

                        $healthy = $false

                        for ($i = 0; $i -lt 15; $i++) {
                            Start-Sleep -Seconds 2

                            try {
                                $response = Invoke-WebRequest `
                                    -Uri "http://localhost:18181/" `
                                    -TimeoutSec 3 `
                                    -UseBasicParsing

                                if ($response.StatusCode -eq 200) {
                                    $healthy = $true
                                    break
                                }
                            } catch {
                                # Retry while Nginx starts
                            }
                        }

                        if (-not $healthy) {
                            throw "Application health check failed."
                        }

                        Write-Host "Build and health check passed: $image"
                    }
                    finally {
                        docker rm -f $container 2>$null | Out-Null
                    }
                '''
            }
        }

        stage('Registry Diagnostics') {
            steps {
                powershell '''
                    $ErrorActionPreference = 'Stop'

                    Write-Host "Checking registry HTTPS endpoint..."

                    curl.exe -k -sS -o NUL `
                        -w "Registry HTTP status: %{http_code}`n" `
                        https://localhost:5000/v2/

                    Write-Host "Docker daemon proxy configuration:"
                    docker info | Select-String 'HTTP Proxy|HTTPS Proxy|No Proxy'
                '''
            }
        }

        stage('Push to Private Registry') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'registry-creds-v2',
                        usernameVariable: 'REGISTRY_USERNAME',
                        passwordVariable: 'REGISTRY_PASSWORD'
                    )
                ]) {
                    powershell '''
                        $ErrorActionPreference = 'Stop'

                        if ([string]::IsNullOrWhiteSpace($env:REGISTRY_USERNAME)) {
                            throw "Registry username was not supplied."
                        }

                        if ([string]::IsNullOrEmpty($env:REGISTRY_PASSWORD)) {
                            throw "Registry password was not supplied."
                        }

                        Write-Host "Registry username: $env:REGISTRY_USERNAME"
                        Write-Host "Password supplied: True"
                        Write-Host "Password length: $($env:REGISTRY_PASSWORD.Length)"

                        # Use a fresh Docker config for this build.
                        $env:DOCKER_CONFIG = Join-Path `
                            $env:WORKSPACE ".docker-ci-$env:BUILD_NUMBER"

                        New-Item -ItemType Directory `
                            -Force -Path $env:DOCKER_CONFIG | Out-Null

                        # Prevent inherited proxy variables from affecting
                        # local Docker CLI requests.
                        $env:NO_PROXY = 'localhost,127.0.0.1,::1'
                        $env:no_proxy = $env:NO_PROXY
                        Remove-Item Env:HTTP_PROXY -ErrorAction SilentlyContinue
                        Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
                        Remove-Item Env:http_proxy -ErrorAction SilentlyContinue
                        Remove-Item Env:https_proxy -ErrorAction SilentlyContinue

                        Write-Host "Logging in to private registry..."

                        $env:REGISTRY_PASSWORD |
                            docker login localhost:5000 `
                                --username $env:REGISTRY_USERNAME `
                                --password-stdin

                        if ($LASTEXITCODE -ne 0) {
                            throw "Registry login failed. Check credential and daemon protocol."
                        }

                        $image = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                        Write-Host "Pushing image: $image"

                        docker push $image

                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker image push failed."
                        }

                        Write-Host "Private registry push successful: $image"
                    '''
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Image successfully pushed. Deployment automation is the next step.'
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Build, health check, and registry push completed.'
        }

        failure {
            echo 'FAILED: Inspect the first failing stage in Console Output.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
