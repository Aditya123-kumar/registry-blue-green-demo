
pipeline {
    agent any

    options {
        timestamps()
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
                    $container = "registry-ci-test-$env:BUILD_NUMBER"

                    docker build -t $image .
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker build failed."
                    }

                    try {
                        docker run -d --name $container `
                            -p 127.0.0.1:18181:80 $image

                        if ($LASTEXITCODE -ne 0) {
                            throw "Container startup failed."
                        }

                        $healthy = $false

                        for ($i = 0; $i -lt 15; $i++) {
                            Start-Sleep -Seconds 2
                            try {
                                $response = Invoke-WebRequest `
                                    -Uri "http://localhost:18181/" `
                                    -UseBasicParsing -TimeoutSec 3

                                if ($response.StatusCode -eq 200) {
                                    $healthy = $true
                                    break
                                }
                            } catch {}
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
                    Write-Host "Checking HTTPS registry endpoint..."

                    curl.exe -k -sS -o NUL `
                        -w "Registry HTTP status: %{http_code}`n" `
                        https://localhost:5000/v2/

                    Write-Host "Docker daemon proxy settings:"
                    docker info | Select-String 'HTTP Proxy|HTTPS Proxy|No Proxy'
                '''
            }
        }

        stage('Test Registry Credentials Directly') {
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

                        if ([string]::IsNullOrEmpty($env:REGISTRY_PASSWORD)) {
                            throw "Registry password was not supplied."
                        }

                        Write-Host "Registry username: $env:REGISTRY_USERNAME"
                        Write-Host "Password supplied: True"
                        Write-Host "Password length: $($env:REGISTRY_PASSWORD.Length)"

                        $pair = "$env:REGISTRY_USERNAME`:$env:REGISTRY_PASSWORD"
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
                        $token = [Convert]::ToBase64String($bytes)

                        $headers = @{
                            Authorization = "Basic $token"
                        }

                        try {
                            # Direct HTTPS test: bypass Docker daemon login.
                            # -SkipCertificateCheck is available in PowerShell 7,
                            # but Jenkins may use Windows PowerShell 5.1.
                            # Use a temporary certificate callback for this request.
                            $oldCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback

                            try {
                                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

                                $response = Invoke-WebRequest `
                                    -Uri "https://localhost:5000/v2/" `
                                    -Headers $headers `
                                    -UseBasicParsing `
                                    -TimeoutSec 10

                                Write-Host "Direct registry authentication HTTP status: $($response.StatusCode)"
                            }
                            catch {
                                if ($_.Exception.Response) {
                                    $status = [int]$_.Exception.Response.StatusCode
                                    Write-Host "Direct registry authentication HTTP status: $status"

                                    if ($status -eq 401) {
                                        throw "Direct authentication returned 401. Verify the saved Jenkins password."
                                    }
                                } else {
                                    Write-Host "Direct HTTPS request failed: $($_.Exception.Message)"
                                    throw
                                }
                            }
                            finally {
                                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $oldCallback
                            }
                        }
                        finally {
                            Remove-Variable pair, bytes, token, headers `
                                -ErrorAction SilentlyContinue
                        }
                    '''
                }
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

                        $env:DOCKER_CONFIG = Join-Path `
                            $env:WORKSPACE ".docker-ci-$env:BUILD_NUMBER"

                        New-Item -ItemType Directory -Force `
                            -Path $env:DOCKER_CONFIG | Out-Null

                        Write-Host "Logging in through Docker..."

                        $env:REGISTRY_PASSWORD |
                            docker login localhost:5000 `
                                --username $env:REGISTRY_USERNAME `
                                --password-stdin

                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker registry login failed."
                        }

                        $image = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                        docker push $image

                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker image push failed."
                        }

                        Write-Host "Registry push successful: $image"
                    '''
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Registry push completed. Deployment automation comes next.'
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Build, health check and registry push completed.'
        }

        failure {
            echo 'FAILED: Check the first failed stage in Console Output.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
