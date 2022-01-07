#!/usr/bin/python3
from bs4 import BeautifulSoup
import sys
import subprocess
import warnings
import yaml
warnings.filterwarnings("ignore")
import requests
headers = {'Content-type': 'application/x-www-form-urlencoded; charset=utf-8'}
endpoint="https://doc.trilio.io:5000/8d92edd6-514d-4acd-90f6-694cb8d83336/0061K00000fwkzU"
result = subprocess.check_output("kubectl get ns kube-system -o=jsonpath='{.metadata.uid}'", shell=True)
kubeid = result.decode("utf-8")
data = "kubescope=clusterscoped&kubeuid={0}".format(kubeid)
r = requests.post(endpoint, data=data, headers=headers)
contents=r.content
soup = BeautifulSoup(contents, 'lxml')
sys.stdout = open("license_file1.yaml", "w")
print(soup.body.find('div', attrs={'class':'yaml-content'}).text)
sys.stdout.close()
flag=1
if(flag == 1):
  with open('license_file1.yaml') as f:
    doc = yaml.safe_load(f)
  doc['metadata']['name'] = "test-license-1"

  with open('license_file1.yaml', 'w') as f:
    yaml.dump(doc, f)

result = subprocess.check_output("kubectl apply -f license_file1.yaml -n default", shell=True)
