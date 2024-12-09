pipeline {
  environment {
    ENVIRONMENT = "${env.GIT_BRANCH == "master" ? "prd" : env.GIT_BRANCH}"
    ENV = "${env.GIT_BRANCH == "master" ? "prod" : env.GIT_BRANCH}"
    AWSCRED = "aws-${ENVIRONMENT}"
    REGION = "eu-west-1"
    CLUSTER = "-${ENVIRONMENT}"
    ECS_SERVICE = "${ENVIRONMENT}-productname"
    ECR_REPO  = getRepoURL(env.GIT_BRANCH)
    ARTIFACTORY_TOKEN = "artifactory-auth-user-${ENVIRONMENT}"
  }
  agent {
    kubernetes {
      label 'productcode'
      yamlFile 'yaml/jenkins-agent-'+"${env.BRANCH_NAME == "master" ? "prd" : env.BRANCH_NAME}"+'.yaml'
    }
  }
  stages {
        stage ("podman get secret"){
      
             steps {   

            container('awscli') {
                  
                sh '''
              
                export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
                export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
                export AWS_DEFAULT_REGION=${REGION}
                aws ecr get-login-password   --region  eu-west-1 > secrect.txt
                
                '''
            }
          }   
        }
        //Build the image 
          stage ("Build Image"){
            when {
               anyOf {
                  branch "dev"
                  branch "qa"
                  branch "master"
               }
            }                    
            steps {
                container('podman') {
                    sh '''
                    echo $(<secrect.txt) |  podman login --password-stdin  --username AWS ${ECR_REPO}
                    export REGISTRY_AUTH_FILE=/podman/.docker/auth.json
                    podman build --tag ${ARTIFACTORY_DOCKER_IMAGE}:${BUILD_NUMBER} -f ${WORKSPACE}/Dockerfile .
                    podman push ${ARTIFACTORY_DOCKER_IMAGE}:${BUILD_NUMBER} oci-archive:${ARTIFACTORY_DOCKER_IMAGE}.tar
                    '''
                }   
            }
        }
        //Container Scan if needed for security purposes
        stage("Container Scan") {
            when {
               anyOf {
                  branch "dev"
                  branch "qa"
                  branch "master"
               }
            }            
            steps {
                container('aquacli') {
                    withVault([configuration: configuration, vaultSecrets: secrets]) {
                        sh '''
                        /opt/aquascans/scannercli scan --checkonly --dockerless -H https://aqua.css.projectcode.com/ -U ${USERNAME} -P ${PASSWORD} --oci-archive ${ARTIFACTORY_DOCKER_IMAGE}.tar ${ARTIFACTORY_DOCKER_REGISTRY}/${ARTIFACTORY_DOCKER_IMAGE}:${BUILD_NUMBER}
                        '''
                    }
                }   
            }                         
        } 
        //Push to the Artifactory
        stage("Push Image") {
            when {
               anyOf {
                  branch "dev"
                  branch "qa"
                  branch "master"
               }
            }                    
            steps {
                container('podman') {
                    sh '''
                        
                        podman tag ${ARTIFACTORY_DOCKER_IMAGE}:${BUILD_NUMBER} ${ECR_REPO}:${BUILD_NUMBER}
                        podman tag ${ARTIFACTORY_DOCKER_IMAGE}:${BUILD_NUMBER} ${ECR_REPO}:latest
                        
                        podman push ${ECR_REPO}:${BUILD_NUMBER}
                        podman push ${ECR_REPO}:latest


                    '''
                }
            }
        }  
 
    //Awaiting for Deployment Approval         
        stage('Approve') {
	        when {
                anyOf { branch "qa"; branch "master"; branch "dev" }
            }
            steps {
                script {
                emailext mimeType: 'text/html',
                 subject: "[Jenkins]${currentBuild.fullDisplayName} > Deployment to ${env.ENVIRONMENT} is waiting for approval ",
                 to: "${EMAIL_INFORM}",
                 body: '''<a href="${BUILD_URL}input">click to approve</a>'''

        def userInput = input id: 'userInput',
                              message: 'Let\'s promote?'
                 }
            }
        }

        //Deployment to the ECS
        stage ('Deploy') {
      
            steps {
            
                container('awscli') {
                sh '''
                echo "aws version: `aws --version`"
                aws sts assume-role-with-web-identity --role-arn $AWS_ROLE_ARN --role-session-name posisbuild --web-identity-token file://$AWS_WEB_IDENTITY_TOKEN_FILE  --duration-seconds 1000 > ${WORKSPACE}/irp-cred.txt
                aws ecs update-service --cluster ${CLUSTER} --service ${ECS_SERVICE} --force-new-deployment
                '''
                }
            }   
        }
    }

}
//Getting Email Address for approval
def getEmailAddressesForApproval(branchName) {
    if("master".equals(branchName)) {
        return "<Email address";
    } else if ("qa".equals(branchName)) {
        return "<Email address>";
    } else if ("dev".equals(branchName)) {
        return "<Email address>";
    }
}

//Getting Repourl for the ECR
def getRepoURL(branchName) {
    if("master".equals(branchName)) {
        return '<Accountid>.dkr.ecr.eu-west-1.amazonaws.com/productcode-prd';
    } else if ("qa".equals(branchName)) {
        return '<Accountid>.dkr.ecr.eu-west-1.amazonaws.com/productcode-qa';
    } else if ("dev".equals(branchName)) {
        return '<Accountid>.dkr.ecr.eu-west-1.amazonaws.com/productcode-dev';
    }
}
//Getting ARN for branchlevel access
def getARN(branchName) {
    if("master".equals(branchName)) {
        return "<Accountid>";
    } else if ("qa".equals(branchName)) {
        return "<Accountid>";
    } else if ("dev".equals(branchName)){
      return "<Accountid>";
    }
}
