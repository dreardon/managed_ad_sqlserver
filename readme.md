# Managed AD with Cloud SQL for SQL Server

## Overview
This project sets up a Google Cloud [Managed AD](https://cloud.google.com/managed-microsoft-ad/docs/overview) instance with a [Cloud SQL for SQL Server](https://cloud.google.com/sql/docs/sqlserver/) instance [joined](https://cloud.google.com/sql/docs/sqlserver/configure-ad) to the Managed AD domain. Additionally, it demonstrates an AD authenticated user, in Windows and Linux, being able to seamlessly log into the Cloud SQL for SQL Server instance if they're already authenticated into the domain. 

This repository borrows heavily from the following Google Cloud documentation:
- [Managed AD: Create a Domain](https://cloud.google.com/managed-microsoft-ad/docs/create-domain)
- [Managed Microsoft AD with Cloud SQ](https://cloud.google.com/sql/docs/sqlserver/configure-ad)
- [Overview and Prerequisites](https://cloud.google.com/sql/docs/sqlserver/ad#prerequisites-for-integration)
- [Join Linux to Managed AD](https://cloud.google.com/managed-microsoft-ad/docs/os-versions#linux-domain-join)

## Google Disclaimer
This is not an officially supported Google product

## Setup Environment
```bash
#Setup Environment variables
export ORGANIZATION_ID= #e.g. 123456789876
export PROJECT_NAME= #e.g. ad-sql
export REGION= #e.g. us-central1
export BILLING_ACCOUNT= #e.g. 111111-222222-333333
export SQL_INSTANCE_NAME= #e.g. example-sql-instance
export DB_ROOT_PASSWORD=[DB_ROOT_PASSWORD]
export DB_NAME= #e.g. example-db-name
export REGION= #e.g. us-central1
export ZONE= #e.g. us-central1-c
export NETWORK_NAME= #e.g. demo-network
export SUBNET_RANGE= #e.g. 10.128.0.0/20 
export AD_DOMAIN= #e.g. ad.example.com
export AD_DOMAIN_CIDR= #e.g. 192.168.0.0/24

#Create Project
gcloud config unset project
gcloud config unset billing/quota_project
printf 'Y' | gcloud projects create --name=$PROJECT_NAME --organization=$ORGANIZATION_ID
while [ -z "$PROJECT_ID" ]; do
  export PROJECT_ID=$(gcloud projects list --filter=name:$PROJECT_NAME --format 'value(PROJECT_ID)')
done
export PROJECT_NUMBER=$(gcloud projects list --filter=id:$PROJECT_ID --format 'value(PROJECT_NUMBER)')
printf 'y' |  gcloud beta billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT

gcloud config set project $PROJECT_ID

#Enable APIs
printf 'y' |  gcloud services enable compute.googleapis.com --project $PROJECT_ID
printf 'y' |  gcloud services enable osconfig.googleapis.com --project $PROJECT_ID
printf 'y' |  gcloud services enable sqladmin.googleapis.com --project $PROJECT_ID
printf 'y' |  gcloud services enable servicenetworking.googleapis.com --project $PROJECT_ID
printf 'y' |  gcloud services enable cloudresourcemanager.googleapis.com --project $PROJECT_ID
printf 'y' |  gcloud services enable managedidentities.googleapis.com --project $PROJECT_ID
printf 'y' |  gcloud services enable dns.googleapis.com --project $PROJECT_ID
printf 'y' |  gcloud services enable iam.googleapis.com --project $PROJECT_ID

gcloud auth application-default set-quota-project $PROJECT_ID
printf 'Y' | gcloud config set compute/region $REGION
gcloud config set billing/quota_project $PROJECT_ID
```

## Setup Network
```bash
#Setup Network
gcloud compute networks create $NETWORK_NAME \
    --project=$PROJECT_ID \
    --subnet-mode=custom 
gcloud compute networks subnets create $NETWORK_NAME-subnet \
    --project=$PROJECT_ID \
    --network=$NETWORK_NAME \
    --range=$SUBNET_RANGE \
    --region=$REGION

#Setup NAT
gcloud compute routers create nat-router \
  --project=$PROJECT_ID \
  --network $NETWORK_NAME \
  --region $REGION
gcloud compute routers nats create nat-config \
  --router-region $REGION \
  --project=$PROJECT_ID \
  --router nat-router \
  --nat-all-subnet-ip-ranges \
  --auto-allocate-nat-external-ips
  ```

## Create Managed Domain
```bash
#Managed AD will take about 20 minutes to provision
gcloud active-directory domains create $AD_DOMAIN \
    --reserved-ip-range=$AD_DOMAIN_CIDR --region=$REGION \
    --authorized-networks=projects/$PROJECT_ID/global/networks/$NETWORK_NAME \
    --enable-audit-logs \
    --project=$PROJECT_ID

export AD_ADMIN_USER=$(gcloud active-directory domains describe $AD_DOMAIN | awk '/admin:/ {print $2}')
export AD_ADMIN_PASSWORD=$(echo "Y" | gcloud active-directory domains reset-admin-password $AD_DOMAIN | awk '/password:/ {print $2}')
```

## Setup Per-product, Per-Project Identities
```bash
gcloud beta services identity create --service=sqladmin.googleapis.com \
    --project=$PROJECT_NUMBER

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloud-sql.iam.gserviceaccount.com \
    --role=roles/managedidentities.sqlintegrator
```

## Setup MSSQL
```bash
gcloud compute addresses create google-managed-services-default \
    --global \
    --purpose=VPC_PEERING \
    --prefix-length=16 \
    --description="Peering range for Google services" \
    --network=$NETWORK_NAME \
    --project=$PROJECT_ID

gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=google-managed-services-default \
    --network=$NETWORK_NAME \
    --project=$PROJECT_ID

gcloud sql instances create $SQL_INSTANCE_NAME \
    --database-version=SQLSERVER_2022_STANDARD \
    --project $PROJECT_ID \
    --region=$REGION \
    --cpu=1 \
    --memory=4GB \
    --root-password=$DB_ROOT_PASSWORD \
    --no-assign-ip \
    --network=$NETWORK_NAME \
    --active-directory-domain=$AD_DOMAIN

gcloud sql databases create $DB_NAME \
  --instance=$SQL_INSTANCE_NAME
```

## Example Windows Compute Instance
```bash

export WINDOWS_VM_NAME=test-windows-vm
export WINDOWS_SCRIPT_URL="https://raw.githubusercontent.com/GoogleCloudPlatform/managed-microsoft-activedirectory/main/domain_join.ps1"

gcloud iam service-accounts create non-default-win-compute-sa \
    --display-name="Non-Default Windows Compute Service Account"
while [ -z "$GSA_WIN_EMAIL" ]; do
  export GSA_WIN_EMAIL=$(gcloud iam service-accounts list --filter="displayName:Non-Default Windows Compute Service Account" --format='value(email)')
done

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GSA_WIN_EMAIL" \
    --role="roles/managedidentities.domainJoin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GSA_WIN_EMAIL"  \
    --role="roles/logging.logWriter"

gcloud compute instances create $WINDOWS_VM_NAME \
    --metadata=windows-startup-script-url=$WINDOWS_SCRIPT_URL,managed-ad-domain=projects/$PROJECT_ID/locations/global/domains/$AD_DOMAIN,managed-ad-domain-join-failure-stop=TRUE,enable-guest-attributes=TRUE,enable-osconfig=true,enable-oslogin=true \
    --service-account=$GSA_WIN_EMAIL \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=$NETWORK_NAME-subnet,no-address  \
    --zone=$ZONE \
    --machine-type=n2-standard-2 \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --image-project=windows-cloud \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --image-family=windows-2022 \
    --metadata-from-file=windows-startup-script-ps1=./windows-vm-script.ps1
```

#### Log in to VM
- NOTE: [Google recommends](https://cloud.google.com/compute/docs/instances/startup-scripts/windows) waiting 10 minutes for the startup script above to complete
- Optional: IAP Tunnel for Windows RDP
```bash
gcloud compute start-iap-tunnel $WINDOWS_VM_NAME 3389 \
    --local-host-port=localhost:63369 \
    --zone=$ZONE \
    --project $PROJECT_ID
```

#### Windows Validation
  - Windows VM should automatically join the domain
  - Log into Windows VM with Domain Admin username/password #e.g. $AD_ADMIN_USER@$AD_DOMAIN
  - Ensure sqlcmd is available (if not, run the following on the machine ./windows-vm-script.ps1)
  - Connect to the database with default Cloud SQL admin credentials (CONNECTION):
    - Private FQDN Connection # e.g. private.$SQL_INSTANCE_NAME.$REGION.$PROJECT_ID.cloudsql.$AD_DOMAIN
    - SQL Auth Proxy Connection # e.g. proxy.$SQL_INSTANCE_NAME.$REGION.$PROJECT_ID.cloudsql.$AD_DOMAIN
    - Use sqlcmd -S [CONNECTION] -U sqlserver -P [DB_ROOT_PASSWORD]
  - Create Active Directory Login for a Domain User (example below)
    - CREATE LOGIN [ad\setupadmin] FROM WINDOWS;
    - USE "example-db-name";
    - CREATE USER setupadmin FOR LOGIN [ad\setupadmin];
    - GRANT SELECT, INSERT, UPDATE, DELETE ON DATABASE::"example-db-name" TO setupadmin;
  - Validation
    - Log into database as Domain User:
    - sqlcmd: sqlcmd -S private.$SQL_INSTANCE_NAME.$REGION.$PROJECT_ID.cloudsql.$AD_DOMAIN -C
    - Run query to validate access:
    - SELECT HAS_DBACCESS ( 'example-db-name' ); #Should return 1
    - sqlcmd shouldn't require a username or password because Windows Domain authentication is successful

## Example Linux Compute Instance
[![Example Video](https://raw.githubusercontent.com/dreardon/managed_ad_sqlserver/main/media/managed_ad_sql_server_linux.png)](https://raw.githubusercontent.com/dreardon/managed_ad_sqlserver/main/media/managed_ad_sql_server_linux.mp4)

https://github.com/user-attachments/assets/a40b47b0-f6f1-44a4-9f33-cf6e7f97b48b

```bash

export LINUX_VM_NAME=test-ubuntu-vm

gcloud iam service-accounts create non-default-lin-compute-sa \
    --display-name="Non-Default Linux Compute Service Account"

while [ -z "$GSA_LIN_EMAIL" ]; do
  export GSA_LIN_EMAIL=$(gcloud iam service-accounts list --filter="displayName:Non-Default Linux Compute Service Account" --format='value(email)')
done 

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GSA_LIN_EMAIL"  \
    --role="roles/logging.logWriter"  

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GSA_LIN_EMAIL" \
    --role="roles/managedidentities.domainJoin"

#Create Linux Example VM
gcloud compute instances create $LINUX_VM_NAME \
    --service-account=$GSA_LIN_EMAIL \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=$NETWORK_NAME-subnet,no-address \
    --zone=$ZONE \
    --machine-type=n2-standard-2 \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --image-project=ubuntu-os-cloud \
    --shielded-secure-boot \
    --metadata=enable-osconfig=true,enable-oslogin=true \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --image-family=ubuntu-2204-lts \
    --metadata-from-file=startup-script=./ubuntu-vm-script.sh

# Join Linux VM to Managed AD via Identity Aware Proxy (IAP)
# NOTE: Google recommends waiting about 1 minute for the startup script above to complete; the command below provide a delay
# https://cloud.google.com/compute/docs/instances/startup-scripts/linux
gcloud compute ssh $LINUX_VM_NAME  \
  --zone $ZONE \
  --tunnel-through-iap \
  --project $PROJECT_ID \
  --command="until [ -e "/etc/krb5.conf" ]; do
               echo 'Waiting for start-up script to complete'; \
               sleep 10;
             done; \
             echo $AD_ADMIN_PASSWORD | sudo realm join $AD_DOMAIN --verbose -U $AD_ADMIN_USER; \
             sudo pam-auth-update --enable mkhomedir; \
             echo 'ad_gpo_access_control = permissive' | sudo tee -a /etc/sssd/sssd.conf; \
             sudo systemctl restart sssd;" \
  -- -t

#Log in to VM
#Optional: Log in via IAP
gcloud compute ssh $LINUX_VM_NAME  \
  --zone $ZONE \
  --tunnel-through-iap \
  --project $PROJECT_ID

#Switch to Managed AD user
su - setupadmin@[AD_DOMAIN]

#Validate Cloud SQL for SQL Server Access, example below:
  - Log into database as Domain User:
  - sqlcmd: /opt/mssql-tools18/bin/sqlcmd -S private.[SQL_INSTANCE_NAME].[REGION].[PROJECT_ID].cloudsql.[AD_DOMAIN] -C
  - Run query to validate access:
  - SELECT HAS_DBACCESS ( 'example-db-name' ); #Should return 1
  - sqlcmd shouldn't require a username or password because Windows Domain authentication is successful
```
