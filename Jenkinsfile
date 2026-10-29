
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        REGISTRY = 'localhost:5000'
        IMAGE_NAME = 'localhost:5000/flask-python-app'
        APP_PORT = '5000'
        BLUE_PORT = '8111'
        GREEN_PORT = '8112'
        PROXY_PORT = '8083'
    }

    stages {
        stage('Checkout and Build') {
            steps {
                bat 'docker version'

                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $tag = "build-$env:BUILD_NUMBER"
                    $image = "$env:IMAGE_NAME`:$tag"

                    docker build -t $image .
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker image build failed."
                    }

                    $testName = "flask-ci-test-$env:BUILD_NUMBER"

                    try {
                        docker run -d --name $testName -p 127.0.0.1:18181:5000 $image
                        if ($LASTEXITCODE -ne 0) {
                            throw "Test container failed to start."
                        }

                        $healthy = $false

                        for ($i = 0; $i -lt 20; $i++) {
                            Start-Sleep -Seconds 2

                            try {
                                $response = Invoke-RestMethod `
                                    -Uri "http://localhost:18181/health" `
                                    -TimeoutSec 3

                                if ($response.status -eq "healthy") {
                                    $healthy = $true
                                    break
                                }
                            } catch {
                                # App may still be starting.
                            }
                        }

                        if (-not $healthy) {
                            throw "Flask health check failed at /health."
                        }

                        Write-Host "Image build and health check passed: $image"
                    }
                    finally {
                        docker rm -f $testName 2>$null | Out-Null
                    }
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

                        $image = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                        # Use cmd.exe for password-stdin on Windows.
                        # The actual password is not written to the build log.
                        $loginCommand = 'echo %REGISTRY_PASSWORD%| docker login https://localhost:5000 --username %REGISTRY_USERNAME% --password-stdin'
                        & cmd.exe /d /s /c $loginCommand

                        if ($LASTEXITCODE -ne 0) {
                            throw "Private registry login failed."
                        }

                        docker push $image
                        if ($LASTEXITCODE -ne 0) {
                            throw "Image push failed: $image"
                        }

                        Write-Host "Image pushed successfully: $image"
                    '''
                }
            }
        }

        stage('Deploy and Verify') {
            steps {
                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $image = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                    Write-Host "Image is available in the registry: $image"
                    Write-Host "Deployment is not being changed automatically by this stage."
                    Write-Host "Use your existing blue-green deployment configuration after confirming the registry push."
                '''
            }
        }
    }

    post {
        success {
            echo 'Build and registry push completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Check the first failing stage in the console log.'
        }
        always {
            echo 'Pipeline execution finished.'
        }
    }
}
