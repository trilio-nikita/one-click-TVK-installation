#!/bin/bash


#This program is use to install/configure/test TVK product with one click and few required inputs



#This module is used to perform preflight check which checks if all the pre-requisites are satisfied before installing Triliovault for Kubernetes application in a Kubernetes cluster

preflight_checks()
{
  ret=$(kubectl krew 2>/dev/null)
  if [[ -z "$ret" ]];then
    echo "Please install krew plugin and then try.For information on krew installation please visit:"
    echo "https://krew.sigs.k8s.io/docs/user-guide/setup/install/"
    exit 1
  fi
  plugin_url='https://github.com/trilioData/tvk-plugins.git'
  kubectl krew index add tvk-plugins $plugin_url 2>/dev/null
  kubectl krew install tvk-plugins/tvk-preflight 
  read -p "Provide storageclass to be used for TVK/Application Installation(storageclass with default annotation): " storage_cls
  if [[ -z "$storage_cls" ]];then
    storage_cls=`kubectl get storageclass | grep -w '(default)' | awk  '{print $1}'`
  fi
  check=`kubectl tvk-preflight --storageclass $storage_cls | tee /dev/tty`
  check_for_fail=`echo $check | grep  'Some Pre-flight Checks Failed!'`
  if [[ -z "$ret" ]];then
    echo "All preflight checks are done and you can proceed"
  else
    echo "There are some failures"
    read -p "Do you want to proceed?y/n: " opt
    if [[ $opt -ne "Y" ]] || [[ $opt -ne "y" ]];then
      exit 1
    fi
  fi

}

#This module is used to install TVK along with its free trial license
install_tvk()
{
  #Install helm3
  curl -s https://get.helm.sh/helm-v3.4.0-linux-amd64.tar.gz | tar xz 2>/dev/null
  ./linux-amd64/helm version >/dev/null 2>/dev/null
  cp linux-amd64/helm /usr/local/bin/ 2>/dev/null

  # Add helm repo and install triliovault-operator chart
  helm repo add triliovault-operator http://charts.k8strilio.net/trilio-stable/k8s-triliovault-operator >/dev/null 2>/dev/null
  helm repo add triliovault http://charts.k8strilio.net/trilio-stable/k8s-triliovault >/dev/null 2>/dev/null
  helm repo update >/dev/null 2>/dev/null
  read -p "Please provide the operator version to be installed(2.1.0): " operator_version
  read -p "Please provide the triliovault manager version(v2.1.1-alpha): " triliovault_manager_version
  if [[ -z "$operator_version" ]];then
    operator_version='2.1.0'
  fi
  if [[ -z "$triliovault_manager_version" ]];then
    triliovault_manager_version='v2.1.1-alpha'
  fi
  
  # Install triliovault operator
  echo "Installing Triliovault operator..."
  helm install triliovault-operator triliovault-operator/k8s-triliovault-operator --version $operator_version 2>/dev/null

  runtime="10 minute"
  endtime=$(date -ud "$runtime" +%s)
  while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get pods -l release=triliovault-operator 2>/dev/null | grep Running` ]]
  do
      echo "........................"
      sleep 10
  done
  if ! [[ `kubectl get pods -l release=triliovault-operator 2>/dev/null | grep Running` ]]; then
      echo "TVO installation failed"
      exit 1
  fi
  # Create TrilioVaultManager CR
  yq eval -i '.spec.trilioVaultAppVersion="'$triliovault_manager_version'" | .spec.trilioVaultAppVersion style="double"' TVM.yaml 2>/dev/null
  kubectl apply -f TVM.yaml >/dev/null 2>/dev/null
  echo "Installing Triliovault manager...."
  runtime="10 minute"
  endtime=$(date -ud "$runtime" +%s)
  while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get pods -l app=k8s-triliovault-control-plane 2>/dev/null | grep Running` ]]
  do
    echo "........................"  
    sleep 2
  done
  runtime="10 minute"
  endtime=$(date -ud "$runtime" +%s)
  while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get pods -l app=k8s-triliovault-admission-webhook 2>/dev/null | grep Running` ]]
  do
      sleep 10
  done
  if ! [[ `kubectl get pods -l app=k8s-triliovault-control-plane 2>/dev/null | grep Running` ]] && [[ `kubectl get pods -l app=k8s-triliovault-admission-webhook 2>/dev/null | grep Running` ]]; then
      echo "TVM installation failed"
      exit 1
  fi
  install_license
}


#This module is use to install license
install_license(){
  echo "Installing Freetrial license..."
  #Install required packages
  sudo apt update >/dev/null 2>/dev/null
  yes | sudo apt install python3-pip >/dev/null 2>/dev/null
  pip3 install beautifulsoup4 >/dev/null 2>/dev/null
  pip3 install lxml >/dev/null 2>/dev/null

  #install trilio license
  python3 install_license.py

}


#This module is used to configure TVK UI
configure_ui()
{
 echo -e "TVK UI can be accessed using \n1.Loadbalancer \n2.Nodeport \n3.Port Forwarding"
 read -p "Please enter option: " option
 if [[ -z "$option" ]]; then
      option=2
 fi
 if [ ${option} -eq 3 ];then
   echo "kubectl port-forward --address 0.0.0.0 svc/k8s-triliovault-ingress-gateway 80:80 &"
   echo "The above command will start forwarding TVK management console traffic to the localhost IP of 127.0.0.1 via port 80"
 fi
 if [ ${option} -eq 2 ];then
   configure_nodeport_for_tvkui
 fi
 if  [ ${option} -eq 1 ];then
   configure_loadbalancer_for_tvkUI
 fi

}

#This function is used to configure TVK UI through nodeport
configure_nodeport_for_tvkui()
{
  read -p "Please enter hostname for a cluster: " tvkhost_name
  gateway=`kubectl get pods --no-headers=true | awk '/k8s-triliovault-ingress-gateway/{print $1}'`
  node=`kubectl get pods $gateway -o jsonpath='{.spec.nodeName}'`
  ip=`kubectl get node trilio-test2-default-pool-8hckg  -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}'`
  port=`kubectl get svc k8s-triliovault-ingress-gateway  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}'`
  kubectl patch ingress k8s-triliovault-ingress-master -p '{"spec":{"rules":[{"host":"'${tvkhost_name}-tvk.com'"}]}}'
  echo "For accesing UI, create an entry in /etc/hosts file for the IPs like '$ip  $tvkhost_name-tvk.com'"
  echo "After creating an entry,TVK UI can be accessed through http://$tvkhost_name-tvk.com:$port"
  echo "For https access, please refer - https://docs.trilio.io/kubernetes/management-console/user-interface/accessing-the-ui" 
}

#This function is used to configure TVK UI through Loadbalancer
configure_loadbalancer_for_tvkUI()
{
 read -p "Please enter domainname for cluster: " domain
 read -p "Please enter host name  for a cluster: " tvkhost_name
 read -p "Please enter cluster name: " cluster_name 
 kubectl patch svc k8s-triliovault-ingress-gateway -p '{"spec": {"type": "LoadBalancer"}}' >/dev/null 2>/dev/null
 val_status=`kubectl get svc k8s-triliovault-ingress-gateway -o 'jsonpath={.status.loadBalancer}'`
 runtime="20 minute"
 endtime=$(date -ud "$runtime" +%s)
 echo "configuring......This may take some time"
 while [[ $(date -u +%s) -le $endtime ]] && [[ $val_status == '{}' ]]
 do
    val_status=`kubectl get svc k8s-triliovault-ingress-gateway -o 'jsonpath={.status.loadBalancer}'` 
    echo "....................."
    sleep 5
 done
 if [[ $val_status == '{}' ]]
 then
    echo "Loadbalancer taking time to get External IP"
    exit 1
 fi
 external_ip=`kubectl get svc k8s-triliovault-ingress-gateway -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'`
 kubectl patch ingress k8s-triliovault-ingress-master -p '{"spec":{"rules":[{"host":"'${tvkhost_name}.${domain}'"}]}}' >/dev/null 2>/dev/null
 doctl compute domain records create ${domain} --record-type A --record-name ${tvkhost_name} --record-data ${external_ip} >/dev/null 2>/dev/null
 doctl kubernetes cluster kubeconfig show ${cluster_name} > config_${cluster_name} 
 link="http://${tvkhost_name}.${domain}/login"
 echo "You can access TVK UI: $link"
 echo "provide config file stored at location: $PWD/config_${cluster_name}"
 echo "Info:UI may take 30 min to come up"
}



#This module is used to create target to be used for TVK backup and restore
create_target()
{
   echo -e "Target can be created on NFS or s3 compatible storage\n1.NFS(default) \n2.DOKs S3"
   read -p "select option: " option
   if [[ -z "$option" ]]; then
      option=1
   fi
   if [ $option -eq 2 ];then
    yes | sudo apt-get install s3cmd >/dev/null 2>/dev/null
    echo "for creation of bucket, please provide input"
    read -p "Access_key: " access_key
    read -p "Secret_key: " secret_key
    read -p "Host Base(nyc3.digitaloceanspaces.com): " host_base
    if [[ -z "$host_base" ]]; then
      host_base="nyc3.digitaloceanspaces.com"
    fi
    read -p "Host Bucket(%(bucket)s.nyc3.digitaloceanspaces.com): " host_bucket
    if [[ -z "$host_bucket" ]]; then
      host_bucket="%(bucket)s.nyc3.digitaloceanspaces.com"
    fi
    read -p "gpg_passphrase: " gpg_passphrase
    read -p "Bucket Name: " bucket_name
    read -p "Target Name: " name
    read -p "Target Namespace: " namespace
    region="$( cut -d '.' -f 1 <<< "$host_base" )"
    for i in access_key secret_key host_base host_bucket gpg_passphrase
    do
      sed -i "s/^\($i\s*=\s*\).*$/\1${!i}/" s3cfg_config
      sudo cp s3cfg_config $HOME/.s3cfg 
    done
    #create bucket
    s3cmd mb s3://$bucket_name 
    #create S3 target
    url="https://$host_base"
    yq eval -i '.metadata.name="'$name'"' target.yaml 2>/dev/null
    yq eval -i '.metadata.namespace="'$namespace'"' target.yaml 2>/dev/null
    #yq write --inplace target.yaml metadata.name $name
    #yq write --inplace target.yaml metadata.namespace $namespace
    yq eval -i '.spec.objectStoreCredentials.url="'$url'" | .spec.objectStoreCredentials.url style="double"' target.yaml 2>/dev/null
    yq eval -i '.spec.objectStoreCredentials.accessKey="'$access_key'" | .spec.objectStoreCredentials.accessKey style="double"' target.yaml 2>/dev/null
    yq eval -i '.spec.objectStoreCredentials.secretKey="'$secret_key'" | .spec.objectStoreCredentials.secretKey style="double"' target.yaml 2>/dev/null
    yq eval -i '.spec.objectStoreCredentials.bucketName="'$bucket_name'" | .spec.objectStoreCredentials.bucketName style="double"' target.yaml 2>/dev/null
    yq eval -i '.spec.objectStoreCredentials.region="'$region'" | .spec.objectStoreCredentials.region style="double"' target.yaml 2>/dev/null
    kubectl apply -f target.yaml 
  fi
  if [ $option -eq 1 ];then
    read -p "Target Name: " name
    read -p "NFSserver: " nfs_server
    read -p "namespace: " namespace
    read -p "Export Path: " nfs_path
    read -p "NFSoption(nfsvers=4): " option
    read -p "thresholdCapacity: " thresholdCapacity 
    if [[ -z "$option" ]]; then
      option='nfsvers=4'
    fi
    yq eval -i '.metadata.name="'$name'"' nfs_target.yaml 2>/dev/null
    yq eval -i '.metadatanamespace="'$namespace'"' nfs_target.yaml 2>/dev/null
    yq eval -i '.spec.nfsCredentials.nfsExport="'$nfs_server:$nfs_path'"' nfs_target.yaml 2>/dev/null
    yq eval -i '.spec.nfsCredentials.nfsOptions="'$option'"' nfs_target.yaml 2>/dev/null
    yq eval -i '.spec.thresholdCapacity="'$thresholdCapacity'"' nfs_target.yaml 2>/dev/null
    kubectl apply -f nfs_target.yaml
  fi
  echo "Creating target..."
  timeout="10 minute"
  endtime=$(date -ud "$timeout" +%s)
  while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get target $name  -n  $namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep Available` ]] && ! [[ `kubectl get target $name  -n  $namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep Unavailable` ]]
  do
     echo "........................"
     sleep 10
  done
  if ! [[ `kubectl get target $name  -n  $namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep Available` ]]; then
     echo "Failed to create target"
     exit 1
  fi

}


#This module is used to test TVK backup and restore for user.
sample_test()
{
   echo "Please provide input for test demo"
   read -p "Target Name: " name
   read -p "Target Namespace: "  target_ns
   read -p "Backupplan name(trilio-test-backup): " bkplan_name
   read -p "Backup Name(trilio-test-backup): " bk_name
   read -p "Backup Namespace Name(trilio-test-backup): " namespace
   if [[ -z "$namespace" ]]; then
      namespace=trilio-test-backup
   fi
   if [[ -z "$bk_name" ]]; then
      bk_name="trilio-test-backup"
   fi
   if [[ -z "$bkplan_name" ]]; then
      bkplan_name="trilio-test-backup"
   fi
   read -p "whether restore test should also be done?y/n: " rest_opt
   res=`kubectl get ns $namespace 2>/dev/null`
   if [[ -z "$res" ]]; then
     kubectl create ns $namespace 2>/dev/null
   fi
   #Add stable helm repo
   helm repo add stable https://charts.helm.sh/stable >/dev/null 2>/dev/null
   helm repo update >/dev/null 2>/dev/null
   echo "User can take backup in multiple ways"
   echo "Fot this sample test, we are using specific applications, but user can backup using any application."
   echo -e "Select an the backup way\n1.Label based(MySQL)\n2.Namespace based(Wordpress)\n3.Operator based(Postgres Operator)\n4.Helm based(Mongodb)"
   read -p "Select option: " option
   case $option in
      1)
        ## Install mysql helm chart
        helm install mysql-qa stable/mysql -n $namespace
        echo "Installing Application"
        timeout="10 minute"
        endtime=$(date -ud "$timeout" +%s)
        while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get pods -l app=mysql-qa -n $namespace 2>/dev/null | grep Running` ]]
        do
	  echo "........................"
          sleep 10
        done
        if ! [[ `kubectl get pods -l app=mysql-qa -n $namespace 2>/dev/null | grep Running` ]]; then
          echo "Application installation failed"
          exit 1
        fi
        yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml 2>/dev/null	
	yq eval -i '.spec.backupPlanComponents.custom[0].matchLabels.app="mysql-qa"' backupplan.yaml 2>/dev/null
        ;;
      2)
	#Add bitnami helm repo
	helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>/dev/null
        helm install my-wordpress bitnami/wordpress -n $namespace >/dev/null 2>/dev/null
	echo "Installing Application"
        timeout="10 minute"
        endtime=$(date -ud "$timeout" +%s)
        while [[ $(date -u +%s) -le $endtime ]] && [[ `kubectl get pod -l  app.kubernetes.io/instance=my-wordpress -n $namespace -o  jsonpath="{.items[*].status.conditions[*].status}" | grep False` ]]
        do
          echo "........................"
          sleep 10
        done 
	if [[ `kubectl get pod -l  app.kubernetes.io/instance=my-wordpress -n $namespace -o  jsonpath="{.items[*].status.conditions[*].status}" | grep False` ]];then
          echo "Wordpress installation failed"
	  exit 1
	fi
	yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml 2>/dev/null
	;;
      3)
        sed -i "/^\([[:space:]]*namespace: \).*/s//\1$namespace/" postgres-operator/manifests/configmap.yaml
        sed -i "/^\([[:space:]]*namespace: \).*/s//\1$namespace/" postgres-operator/manifests/operator-service-account-rbac.yaml
        sed -i "/^\([[:space:]]*namespace: \).*/s//\1$namespace/" postgres-operator/manifests/postgres-operator.yaml
        sed -i "/^\([[:space:]]*namespace: \).*/s//\1$namespace/" postgres-operator/manifests/api-service.yaml	
	kubectl create -f postgres-operator/manifests/configmap.yaml -n $namespace # configuration
        kubectl create -f postgres-operator/manifests/operator-service-account-rbac.yaml -n $namespace # identity and permissions
        kubectl create -f postgres-operator/manifests/postgres-operator.yaml  -n $namespace # deployment
        kubectl create -f postgres-operator/manifests/api-service.yaml  -n $namespace # operator API to be used by UI
	#check if operator is up and running
	echo "Installing Postgres pperator..."
        timeout="5 minute"
        endtime=$(date -ud "$timeout" +%s)
        while [[ $(date -u +%s) -le $endtime ]] && [[ `kubectl get pod -l name=postgres-operator -n $namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep False` ]]
        do
	  echo "........................"
          sleep 10
        done
        if [[ `kubectl get pod -l name=postgres-operator -n $namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep False` ]];then
          echo "Postgress operator installation failed"
          exit 1
        fi
	#Deploy the operator UI
	#Create a Postgres cluster
	sed -i "/^\([[:space:]]*namespace: \).*/s//\1$namespace/" postgres-operator/manifests/minimal-postgres-manifest.yaml
        kubectl create -f postgres-operator/manifests/minimal-postgres-manifest.yaml -n $namespace
	timeout="15 minute"
	echo "Installing Postgres cluster..."
	endtime=$(date -ud "$timeout" +%s)
        while [[ $(date -u +%s) -le $endtime ]] && [[ `kubectl get pods -l application=spilo -L spilo-role -n $namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep False` ]]
        do
	  echo "........................"
          sleep 10
        done
        if [[ `kubectl get pods -l application=spilo -L spilo-role -n $namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep False` ]];then
          echo "Postgress cluster installation failed"
          exit 1
        fi
	echo -e "You can now access the web interface of postgress operator by port forwarding the UI pod (mind the label selector) and enter localhost:8081 in your browser:\nkubectl port-forward svc/postgres-operator-ui 8081:80 -n $namespace"
	#yq d -i backupplan.yaml spec.backupPlanComponents
	yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml 2>/dev/null
        yq eval -i '.spec.backupPlanComponents.operators[0].operatorId="acid-minimal-cluster"' backupplan.yaml 2>/dev/null
	yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.group="acid.zalan.do" | .spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.group style="double"' backupplan.yaml 2>/dev/null
	yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.version="v1" | .spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.version style="double"' backupplan.yaml 2>/dev/null
	yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.kind="postgresql" | .spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.kind style="double"' backupplan.yaml 2>/dev/null
	yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].objects[0]="acid-minimal-cluster"' backupplan.yaml 2>/dev/null
        yq eval -i '.spec.backupPlanComponents.operators[0].operatorResourceSelector[0].matchLabels.name="postgres-operator"' backupplan.yaml 2>/dev/null
        yq eval -i '.spec.backupPlanComponents.operators[0].applicationResourceSelector[0].matchLabels.application="spilo"' backupplan.yaml 2>/dev/null
	;;
      4)
	helm repo add bitnami https://charts.bitnami.com/bitnami
        helm repo update
        helm install mongotest bitnami/mongodb
	echo "Installing App..."
	timeout="15 minute"
        endtime=$(date -ud "$timeout" +%s)
        while [[ $(date -u +%s) -le $endtime ]] && [[ `kubectl get pod -l app.kubernetes.io/name=mongodb -n test -o  jsonpath="{.items[*].status.conditions[*].stat" | grep False` ]]
        do
	  echo "........................"
          sleep 10
        done
        if [[ `kubectl get pod -l app.kubernetes.io/name=mongodb -n test -o  jsonpath="{.items[*].status.conditions[*].stat" | grep False` ]];then
          echo "Mongodb installation failed"
          exit 1
        fi
        yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml 2>/dev/null
	yq eval -i '.spec.backupPlanComponents.helmReleases[0]="mongotest"' backupplan.yaml 2>/dev/null
	;;
      *)
    	echo "Wrong choice"
        ;;
  esac
   echo "Requested application is installed successfully"
   #Applying backupplan manifest
   yq eval -i '.metadata.name="'$bkplan_name'"' backupplan.yaml 2>/dev/null
   yq eval -i '.metadata.namespace="'$namespace'"' backupplan.yaml 2>/dev/null
   yq eval -i '.spec.backupNamespace="'$namespace'"' backupplan.yaml 2>/dev/null
   yq eval -i '.spec.backupConfig.target.name="'$name'"' backupplan.yaml 2>/dev/null
   yq eval -i '.spec.backupConfig.target.namespace="'$target_ns'"' backupplan.yaml 2>/dev/null
   echo "Creating backupplan..."
   kubectl apply -f backupplan.yaml -n $namespace
  
   timeout="5 minute"
   endtime=$(date -ud "$timeout" +%s)
   while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get backupplan $bkplan_name  -n  $namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep Available` ]]
   do
      echo "........................"
      sleep 10
   done
   if ! [[ `kubectl get backupplan $bkplan_name  -n  $namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep Available` ]]; then
      echo "Backupplan creation failed"
      exit 1
   fi

   #Applying backup manifest
   yq eval -i '.metadata.name="'$bk_name'"' backup.yaml 2>/dev/null
   yq eval -i '.metadata.namespace="'$namespace'"' backup.yaml 2>/dev/null
   yq eval -i '.spec.backupPlan.name="'$bkplan_name'"' backup.yaml 2>/dev/null
   echo "Starting backup..."
   kubectl apply -f backup.yaml -n $namespace

   timeout="60 minute"
   endtime=$(date -ud "$timeout" +%s)
   while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get backup $bk_name -n  $namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep Available` ]] && ! [[ `kubectl get backup $bk_name -n $namespace -o 'jsonpath={.status.status}'  2>/dev/null | grep Failed` ]]
   do
      echo "........................"
      sleep 5
   done
   if ! [[ `kubectl get backup $bk_name -n $namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep Available` ]]; then
      echo "Backup Failed"
      exit 1
   fi 
   if [[ ${rest_opt} == "Y" ]] || [[ ${rest_opt} == "y" ]]
   then
     read -p "Restore Namepsace(trilio-test-rest): " rest_ns
     read -p "Restore name(trilio-test-restore): " rest_name
     if [[ -z "$rest_ns" ]]; then
	rest_ns="trilio-test-rest"
     fi
     kubectl create ns rest_ns 2>/dev/null
     if [[ -z "$rest_name" ]]; then
	rest_name="trilio-test-restore"
     fi
     yq eval -i '.metadata.name="'$rest_name'"' restore.yaml 2>/dev/null
     yq eval -i '.metadata.namespace="'$rest_ns'"' restore.yaml 2>/dev/null
     yq eval -i '.spec.restoreNamespace="'$rest_ns'"' restore.yaml 2>/dev/null
     yq eval -i '.spec.source.target.name="'$name'"' restore.yaml 2>/dev/null
     yq eval -i '.spec.source.target.namespace="'$target_ns'"' restore.yaml 2>/dev/null
     yq eval -i '.spec.source.backup.name="'$bk_name'"' restore.yaml 2>/dev/null
     yq eval -i '.spec.source.backup.namespace="'$namespace'"' restore.yaml 2>/dev/null
     echo "Starting restore..."
     kubectl apply -f restore.yaml -n $rest_ns
   else
     exit
   fi
   timeout="60 minute"
   endtime=$(date -ud "$timeout" +%s)
   while [[ $(date -u +%s) -le $endtime ]] && ! [[ `kubectl get restore $rest_name -n $rest_ns -o 'jsonpath={.status.status}' 2>/dev/null | grep Completed` ]] && ! [[ `kubectl get restore $rest_name -n $rest_ns -o 'jsonpath={.status.status}' 2>/dev/null | grep Failed` ]]
   do
      echo "........................"
      sleep 5
   done
   if ! [[ `kubectl get restore $rest_name -n $rest_ns -o 'jsonpath={.status.status}' 2>/dev/null | grep Completed` ]]; then
      echo "Restore Failed"
      exit 1
   fi 
}




print_usage(){
  echo "
--------------------------------------------------------------
tvk-oneclick - Installs, Configures UI, Create sample backup/restore test
Usage:
kubectl tvk-oneclick [options] [arguments]
Options:
        -h, --help                show brief help
        -n, --noninteractive      run script in non-interactive mode
        -i, --install_tvk         Installs TVK and it's free trial license.
        -c, --configure_ui        Configures TVK UI
        -t, --target              Created Target for backup and restore jobs
        -s, --sample_test         Create sample backup and restore jobs
	-p, --preflight           Checks if all the pre-requisites are satisfied
-----------------------------------------------------------------------
"
}

main()
{
  log_file="logs.txt"
  exec &> >(tee -a "$log_file")
  for i in "$@"; do
    #key="$1"
    case $i in
      -h|--help)
        print_usage
        exit 0
        ;;
      -n|--noninteractive)
        export Non_interact=True
        echo "Flag set to run cleanup in non-interactive mode"
        echo
        ;;
      -i|--install_tvk)
	export TVK_INSTALL=True
	#echo "Flag set to install TVK product"
	shift
	echo
	;;
      -c|--configure_ui)
	export CONFIGURE_UI=True
	#echo "flag set to configure ui"
	echo
	;;
      -t|--target)
	export TARGET=True
        #echo "flag set to create backup target"
	shift
	echo
	;;
      -s|--sample_test)
        export SAMPLE_TEST=True
	#echo "flag set to test sample  backup and restore of application "
	echo
	;;
      -p|--preflight)
	export PREFLIGHT=True
	echo
	;;
      *)
      echo "Incorrect option, check usage below..."
      echo
      print_usage
      exit 1
      ;;
     esac
     shift
  done
  if [ ${PREFLIGHT}  ]
  then
    preflight_checks
  fi
  if [ ${TVK_INSTALL} ]
  then  
    install_tvk
  fi
  if [ ${CONFIGURE_UI} ]
  then
    configure_ui
  fi
  if [ ${TARGET} ]
  then
    create_target   
  fi
  if [ ${SAMPLE_TEST}  ]
  then
    sample_test
  fi
    
}
main $@
