pipeline {
    agent any

    options {
        timestamps()
    }

    environment {
        REGISTRY_URL = 'localhost:5000'
        IMAGE_NAME   = 'localhost:5000/flask-python-app'
        REGISTRY_CREDENTIALS = 'registry-creds-v2'
    }

    stages {

        stage('Checkout and Build') {
            steps {
                echo 'Building application image...'

                powershell '''
                    $ErrorActionPreference = "Stop"

                    $ImageTag = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                    docker build -t $ImageTag .

                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker image build failed."
                    }

                    $ContainerName = "jenkins-health-$env:BUILD_NUMBER"

                    docker run -d --name $ContainerName -p 18181:80 $ImageTag

                    if ($LASTEXITCODE -ne 0) {
                        throw "Temporary application container failed to start."
                    }

                    try {
                        Start-Sleep -Seconds 5

                        $Response = curl.exe -sS -o NUL -w "%{http_code}" http://localhost:18181/

                        if ($LASTEXITCODE -ne 0 -or $Response -ne "200") {
                            throw "Application health check failed. HTTP status: $Response"
                        }

                        Write-Host "Build and health check passed: $ImageTag"
                    }
                    finally {
                        docker rm -f $ContainerName
                    }
                '''
            }
        }

        stage('Registry Diagnostics') {
            steps {
                echo 'Checking registry connectivity and Docker environment...'

                powershell '''
                    Write-Host "=== Docker Context ==="
                    docker context show

                    Write-Host "=== Docker Server ==="
                    docker version --format "Server: {{.Server.Version}}"

                    Write-Host "=== Registry HTTPS test ==="
                    curl.exe -k -sS -o NUL -w "HTTPS status: %{http_code}`n" https://$env:REGISTRY_URL/v2/

                    Write-Host "=== Registry HTTP test ==="
                    curl.exe -sS -o NUL -w "HTTP status: %{http_code}`n" http://$env:REGISTRY_URL/v2/

                    Write-Host "=== Proxy variables ==="
                    Get-ChildItem Env: | Where-Object {
                        $_.Name -match 'proxy'
                    } | ForEach-Object {
                        Write-Host "$($_.Name)=$($_.Value)"
                    }
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
                        $ErrorActionPreference = "Stop"

                        # Bypass proxy for local registry
                        $env:NO_PROXY = "localhost,127.0.0.1"
                        $env:no_proxy = "localhost,127.0.0.1"

                        # Clear proxy variables for this process
                        $env:HTTP_PROXY = ""
                        $env:HTTPS_PROXY = ""
                        $env:ALL_PROXY = ""
                        $env:http_proxy = ""
                        $env:https_proxy = ""
                        $env:all_proxy = ""

                        # Use a separate Docker config for this Jenkins build
                        $env:DOCKER_CONFIG = Join-Path $env:WORKSPACE ".docker-ci-$env:BUILD_NUMBER"
                        New-Item -ItemType Directory -Force -Path $env:DOCKER_CONFIG | Out-Null

                        Write-Host "Logging in to private Docker registry..."

                        $env:REGISTRY_PASSWORD |
                            docker login $env:REGISTRY_URL `
                                --username $env:REGISTRY_USERNAME `
                                --password-stdin

                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker registry login failed."
                        }

                        Write-Host "Registry login successful."

                        $ImageTag = "$env:IMAGE_NAME`:build-$env:BUILD_NUMBER"

                        Write-Host "Pushing image: $ImageTag"

                        docker push $ImageTag

                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker image push failed."
                        }

                        Write-Host "Image pushed successfully: $ImageTag"

                        docker logout $env:REGISTRY_URL
                    '''
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Image build, health check and private registry push completed successfully.'
                echo 'Next step: configure blue-green deployment.'
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Jenkins pipeline completed.'
        }

        failure {
            echo 'FAILED: Check the first failed stage in Console Output.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
