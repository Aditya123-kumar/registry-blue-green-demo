
pipeline {
    agent any

    parameters {
        choice(name: 'VERSION', choices: ['v1', 'v2', 'v3'],
               description: 'Select image version')
    }

    stages {
        stage('Pull Image') {
            steps {
                bat 'docker version'
                bat 'docker pull localhost:5000/flask-app:%VERSION%'
            }
        }
    }
}
