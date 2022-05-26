#!/usr/bin/python3
from bs4 import BeautifulSoup
import requests
import sys
import subprocess
import os
ns = os.getenv('NAMESPACE')
headers = {'Content-type': 'application/x-www-form-urlencoded; charset=utf-8'}
endpoint="https://license.trilio.io/8d92edd6-514d-4acd-90f6-694cb8d83336/0061K00000i9ORf"
command = "kubectl get namespace "+ns+" -o=jsonpath='{.metadata.uid}'"
result = subprocess.check_output(command, shell=True)
kubeid = result.decode("utf-8")
data = "kubescope=clusterscoped&kubeuid={0}".format(kubeid)
r = requests.post(endpoint, data=data, headers=headers)
contents=r.content
soup = BeautifulSoup(contents, 'lxml')
apply_command = soup.body.find('div', attrs={'class':'yaml-content'}).text
print("creating license for "+ns)
result = subprocess.check_output(apply_command.replace('kubectl', 'kubectl -n '+ns), shell=True)
