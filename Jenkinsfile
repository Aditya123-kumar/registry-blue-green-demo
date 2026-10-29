
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        REGISTRY_URL = 'localhost:5000'
        IMAGE_NAME   = 'localhost:5000/flask-python-app'
        CONTAINER_NAME = 'registry-blue-green-app'
        APP_PORT     = '8098'
    }

    stages {
        stage('Checkout and Build') {
            steps {
                echo 'Building application image...'

                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $tag = "build-$env:BUILD_NUMBER"
                    $image = "$env:IMAGE_NAME`:$tag"

                    docker build -t $image .

                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker build failed"
                    }

                    $container = "jenkins-health-$env:BUILD_NUMBER"

                    try {
                        docker run -d --name $container -p 127.0.0.1:18181:80 $image

                        if ($LASTEXITCODE -ne 0) {
                            throw "Temporary container failed to start"
                        }

                        $healthy = $false

                        for ($i = 0; $i -lt 10; $i++) {
                            Start-Sleep -Seconds 2

                            try {
                                $response = Invoke-WebRequest `
                                    -Uri 'http://127.0.0.1:18181/' `
                                    -UseBasicParsing `
                                    -TimeoutSec 5

                                if ($response.StatusCode -eq 200) {
                                    $healthy = $true
                                    break
                                }
                            }
                            catch {
                                # Retry while Nginx starts
                            }
                        }

                        if (-not $healthy) {
                            throw "Application health check failed"
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
                echo 'Checking registry HTTPS endpoint...'

                powershell '''
                    $ErrorActionPreference = 'Stop'

                    $result = & curl.exe -k -sS -o NUL -w "%{http_code}" `
                        "https://$env:REGISTRY_URL/v2/"

                    if ($LASTEXITCODE -ne 0) {
                        throw "Cannot connect to registry over HTTPS"
                    }

                    Write-Host "Registry HTTP status: $result"

                    if ($result -notin @('200', '401')) {
                        throw "Unexpected registry response: $result"
                    }

                    Write-Host "Registry endpoint is reachable."
                '''
            }
        }

        stage('Test Registry Credentials Directly') {
            steps {
                echo 'Docker login will validate registry credentials.'
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

                        $tag = "build-$env:BUILD_NUMBER"
                        $image = "$env:IMAGE_NAME`:$tag"

                        # Use a fresh Docker config for this build.
                        $dockerConfig = Join-Path $env:WORKSPACE ".docker-ci-$env:BUILD_NUMBER"
                        New-Item -ItemType Directory -Force -Path $dockerConfig | Out-Null
                        $env:DOCKER_CONFIG = $dockerConfig

                        try {
                            $env:REGISTRY_PASSWORD |
                                docker login $env:REGISTRY_URL `
                                    --username $env:REGISTRY_USERNAME `
                                    --password-stdin

                            if ($LASTEXITCODE -ne 0) {
                                throw "Docker registry login failed. Check Jenkins credential registry-creds-v2."
                            }

                            Write-Host "Docker registry login succeeded."

                            docker push $image

                            if ($LASTEXITCODE -ne 0) {
                                throw "Docker image push failed: $image"
                            }

                            Write-Host "Image pushed successfully: $image"
                        }
                        finally {
                            docker logout $env:REGISTRY_URL 2>$null | Out-Null
                            Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
                            Remove-Item -Recurse -Force $dockerConfig -ErrorAction SilentlyContinue
                        }
                    '''
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Image build and registry push completed.'
                echo 'Automatic deployment is not configured in this pipeline yet.'
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Image built, health-checked, and pushed to the private registry.'
        }

        failure {
            echo 'FAILED: Check the first failed stage in the Console Output.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}