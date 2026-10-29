
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        REGISTRY   = 'https://localhost:5000'
        IMAGE_NAME = 'localhost:5000/flask-python-app'
        TEST_PORT  = '18181'
    }

    stages {
        stage('Checkout and Build') {
            steps {
                bat 'docker version'

                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $tag = "build-$env:BUILD_NUMBER"
                    $image = "$env:IMAGE_NAME`:$tag"
                    $testName = "web-ci-test-$env:BUILD_NUMBER"

                    docker build -t $image .
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker image build failed."
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
                                    -TimeoutSec 3 `
                                    -UseBasicParsing

                                if ($response.StatusCode -eq 200) {
                                    $healthy = $true
                                    break
                                }
                            } catch {
                                # Wait for Nginx to become ready.
                            }
                        }

                        if (-not $healthy) {
                            throw "Nginx HTTP health check failed."
                        }

                        Write-Host "Build and Nginx health check passed: $image"
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

                        $env:DOCKER_CONFIG = Join-Path $env:WORKSPACE '.docker-ci'
                        New-Item -ItemType Directory -Force `
                            -Path $env:DOCKER_CONFIG | Out-Null

                        try {
                            $env:REGISTRY_PASSWORD |
                                docker login localhost:5000 `
                                    --username $env:REGISTRY_USERNAME `
                                    --password-stdin

                            if ($LASTEXITCODE -ne 0) {
                                throw "Private registry login failed."
                            }

                            docker push $image
                            if ($LASTEXITCODE -ne 0) {
                                throw "Image push failed: $image"
                            }

                            Write-Host "Image pushed successfully: $image"
                        }
                        finally {
                            docker logout localhost:5000 2>$null | Out-Null
                            Remove-Item Env:REGISTRY_PASSWORD `
                                -ErrorAction SilentlyContinue
                            Remove-Item Env:DOCKER_CONFIG `
                                -ErrorAction SilentlyContinue
                            Remove-Item -Recurse -Force `
                                (Join-Path $env:WORKSPACE '.docker-ci') `
                                -ErrorAction SilentlyContinue
                        }
                    '''
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Build and registry push are complete. Blue-green deployment has not been run by this pipeline yet.'
            }
        }
    }

    post {
        success {
            echo 'Build, health check and registry push completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Inspect the first failing stage in Console Output.'
        }
        always {
            echo 'Pipeline execution finished.'
        }
    }
}
