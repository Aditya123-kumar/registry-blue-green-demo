
pipeline {
    agent any

    parameters {
        choice(
            name: 'VERSION',
            choices: ['v1', 'v2', 'v3'],
            description: 'Image version to deploy'
        )

        choice(
            name: 'TARGET_COLOR',
            choices: ['green', 'blue'],
            description: 'Inactive environment to deploy into'
        )
    }

    stages {
        stage('Pull Image') {
            steps {
                bat 'docker version'
                bat 'docker pull localhost:5000/flask-app:%VERSION%'
            }
        }

        stage('Check Active Environment') {
            steps {
                powershell '''
                    $config = Get-Content "C:\\Users\\CEREBRENT PC\\registry-rollback-demo\\proxy\\default.conf" -Raw

                    if ($config -match 'host\\.docker\\.internal:(\\d+)') {
                        $activePort = $Matches[1]
                    } else {
                        throw "Cannot determine active proxy port"
                    }

                    if ($env:TARGET_COLOR -eq "blue") {
                        $targetPort = "8099"
                        $container = "registry-blue"
                    } else {
                        $targetPort = "8100"
                        $container = "registry-green"
                    }

                    if ($activePort -eq $targetPort) {
                        throw "Safety check failed: selected color is LIVE. Choose the inactive color."
                    }

                    Write-Host "Active port: $activePort"
                    Write-Host "Deployment target: $container on port $targetPort"
                '''
            }
        }
    }
}
