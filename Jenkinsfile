pipeline {
    agent any

    parameters {
        choice(name: 'VERSION', choices: ['v1', 'v2', 'v3'])
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/Aditya123-kumar/registry-blue-green-demo.git'
            }
        }

        stage('Pull Image') {
            steps {
                bat 'docker version'
                bat 'docker pull localhost:5000/flask-app:%VERSION%'
            }
        }
    }
}
