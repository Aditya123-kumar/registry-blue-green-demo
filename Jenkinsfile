
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        REGISTRY   = 'localhost:5000'
        IMAGE_NAME = 'localhost:5000/flask-python-app'
        TEST_PORT  = '18181'
    }

    stages {
        stage('Checkout and Build') {
            steps {
                echo 'Building Nginx application...'

                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $tag = "build-$env:BUILD_NUMBER"
                    $image = "$env:IMAGE_NAME`:$tag"
                    $testName = "web-ci-test-$env:BUILD_NUMBER"

                    docker build -t $image .
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker build failed."
                    }

                    try {
                        docker run -d --name $testName `
                            -p "127.0.0.1:$env:TEST_PORT`:80" $image

                        if ($LASTEXITCODE -ne 0) {
                            throw "Test container failed to start."
                        }

                        $healthy = $false

                        for ($i = 0; $i -lt 20; $i++) {
                            Start-Sleep -Seconds 2

                            try {
                                $response = Invoke-WebRequest `
                                    -Uri "http://localhost:$env:TEST_PORT/" `
                                    -UseBasicParsing -TimeoutSec 3

                                if ($response.StatusCode -eq 200) {
                                    $healthy = $true
                                    break
                                }
                            }
                            catch {
                                # Retry while Nginx starts.
                            }
                        }

                        if (-not $healthy) {
                            throw "Nginx health check failed."
                        }

                        Write-Host "Build and health check passed: $image"
                    }
                    finally {
                        docker rm -f $testName 2>$null | Out-Null
                    }
                '''
            }
        }

        stage('Registry Diagnostics') {
            steps {
                powershell '''
                    $env:NO_PROXY = 'localhost,127.0.0.1,::1'
                    $env:no_proxy = $env:NO_PROXY

                    # Show proxy variable names and values for diagnosis.
                    # Do not print credentials or passwords.
                    Write-Host "=== Proxy environment ==="

                    Get-ChildItem Env: |
                        Where-Object { $_.Name -match 'proxy' } |
                        ForEach-Object {
                            Write-Host "$($_.Name)=$($_.Value)"
                        }

                    Write-Host "=== HTTPS registry response ==="
                    curl.exe -k -i https://localhost:5000/v2/

                    Write-Host "=== Docker daemon proxy settings ==="
                    docker info 2>&1 |
                        Select-String -Pattern 'Proxy|Insecure Registries'
                '''
            }
        }

        stage('Push to Private Registry') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'registry-creds',
                        usernameVariable: 'REGISTRY_USERNAME',
                        passwordVariable: 'REGISTRY_PASSWORD'
                    )
                ]) {
                    powershell '''
                        $ErrorActionPreference = 'Stop'

                        $env:NO_PROXY = 'localhost,127.0.0.1,::1'
                        $env:no_proxy = $env:NO_PROXY

                        $env:HTTP_PROXY = ''
                        $env:HTTPS_PROXY = ''
                        $env:ALL_PROXY = ''
                        $env:http_proxy = ''
                        $env:https_proxy = ''
                        $env:all_proxy = ''

                        $image = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"
                        $dockerConfig = Join-Path $env:WORKSPACE '.docker-ci'

                        $env:DOCKER_CONFIG = $dockerConfig
                        New-Item -ItemType Directory -Force `
                            -Path $dockerConfig | Out-Null

                        try {
                            Write-Host "Logging in to HTTPS registry..."

                            $env:REGISTRY_PASSWORD |
                                docker login localhost:5000 --username $env:REGISTRY_USERNAME --password-stdin

                            if ($LASTEXITCODE -ne 0) {
                                throw "Registry login failed."
                            }

                            Write-Host "Registry login succeeded."

                            docker push $image
                            if ($LASTEXITCODE -ne 0) {
                                throw "Image push failed: $image"
                            }

                            Write-Host "Image pushed: $image"
                        }
                        finally {
                            docker logout localhost:5000 2>$null |
                                Out-Null

                            Remove-Item Env:REGISTRY_PASSWORD `
                                -ErrorAction SilentlyContinue

                            Remove-Item Env:DOCKER_CONFIG `
                                -ErrorAction SilentlyContinue

                            Remove-Item -Recurse -Force $dockerConfig `
                                -ErrorAction SilentlyContinue
                        }
                    '''
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Build and registry push completed.'
                echo 'Blue-green deployment will be configured separately.'
                echo 'Existing application has not been replaced.'
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Build, health check and registry push passed.'
        }

        failure {
            echo 'FAILED: Inspect the first failing stage in Console Output.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
