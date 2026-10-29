
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
                echo 'Building the Nginx application image...'

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
                            }
                            catch {
                                # Nginx may still be starting.
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

                        # Bypass proxies for the local registry.
                        $env:NO_PROXY = 'localhost,127.0.0.1,::1'
                        $env:no_proxy = $env:NO_PROXY

                        $env:HTTP_PROXY = ''
                        $env:HTTPS_PROXY = ''
                        $env:ALL_PROXY = ''
                        $env:http_proxy = ''
                        $env:https_proxy = ''
                        $env:all_proxy = ''

                        $image = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                        # Keep Docker authentication separate for this job.
                        $dockerConfig = Join-Path $env:WORKSPACE '.docker-ci'
                        $env:DOCKER_CONFIG = $dockerConfig

                        New-Item -ItemType Directory -Force `
                            -Path $dockerConfig | Out-Null

                        try {
                            # Use HTTPS explicitly for the registry.
                            $env:REGISTRY_PASSWORD |
                                docker login https://localhost:5000 `
                                    --username $env:REGISTRY_USERNAME `
                                    --password-stdin

                            if ($LASTEXITCODE -ne 0) {
                                throw "Registry login failed. Check registry HTTPS, certificate trust and proxy settings."
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

                            Remove-Item -Recurse -Force $dockerConfig `
                                -ErrorAction SilentlyContinue
                        }
                    '''
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Registry push stage passed. Blue-green deployment is not yet automated.'
                echo 'The existing application has not been replaced by this pipeline.'
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Image built, tested and pushed to the private registry.'
        }

        failure {
            echo 'FAILED: Check the first failing stage in Console Output.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
