gcloud services enable config.googleapis.com
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
source ~/.bashrc
gsutil cp gs://qwiklabs-gcp-04-78814cacf3af-resources/multi-mig-http-lb-v2.zip .
unzip -j multi-mig-http-lb-v2.zip -d cepf-iac
cd cepf-iac
PROJECT_ID=$(gcloud config get core/project)
sed -i "s/PROJECT_ID/$PROJECT_ID/g" backend.tf
cd ~/cepf-iac 2>/dev/null || cd cepf-iac 2>/dev/null || true
python3 - << 'EOF'
import re, pathlib

# 1. backend.tf (# TODO 1)
pathlib.Path("backend.tf").write_text("""terraform {
  backend "gcs" {
    bucket = "qwiklabs-gcp-04-78814cacf3af-bucket-tfstate"
  }
}
""")

# 2 & 3. mig.tf (# TODO 2 & # TODO 3)
mig_path = pathlib.Path("mig.tf")
mig_text = mig_path.read_text()
mig_text = re.sub(
    r'^(\s*).*\bTODO\s*2\b.*$',
    r'\1database_version = "POSTGRES_14"',
    mig_text,
    flags=re.MULTILINE
)
mig_text = re.sub(
    r'^(\s*).*\bTODO\s*3\b.*$',
    r'\1target_size = var.target_size',
    mig_text,
    flags=re.MULTILINE
)
mig_path.write_text(mig_text)

# 4. main.tf (# TODO 4)
main_path = pathlib.Path("main.tf")
main_text = main_path.read_text()
main_text = re.sub(
    r'^(\s*).*\bTODO\s*4\b.*$',
    r'\1load_balancing_scheme = "EXTERNAL_MANAGED"',
    main_text,
    flags=re.MULTILINE
)
main_path.write_text(main_text)

print("Todos los # TODO fueron actualizados correctamente!")
EOF

# Inicializar el backend en GCS y aplicar la infraestructura
terraform init -migrate-state -force-copy || terraform init
terraform validate
terraform apply -auto-approve
terraform init -migrate-state -force-copy || terraform init
terraform validate
terraform apply -auto-approve
rm backend.tf
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding $PROJECT_ID   --member="serviceAccount:${SA_EMAIL}"   --role="roles/owner"   --condition=None
cd ~/cepf-iac 2>/dev/null || cd cepf-iac 2>/dev/null || true
# 3a. Crear el bucket gs://qwiklabs-gcp-04-78814cacf3af-infra-source en us-east1
gcloud storage buckets create gs://qwiklabs-gcp-04-78814cacf3af-infra-source   --project=qwiklabs-gcp-04-78814cacf3af   --location=us-east1 || true
# 3b. Subir todos los archivos .tf y start-up.sh a la raíz del bucket
gcloud storage cp *.tf start-up.sh gs://qwiklabs-gcp-04-78814cacf3af-infra-source/
# Limpiar lock en caso de haber cancelado un apply local previo
gcloud storage rm gs://qwiklabs-gcp-04-78814cacf3af-bucket-tfstate/default.tflock 2>/dev/null || true
# 4. Desplegar con Infrastructure Manager (lab-deployment en us-east1)
gcloud infra-manager deployments apply lab-deployment   --project=qwiklabs-gcp-04-78814cacf3af   --location=us-east1   --gcs-source=gs://qwiklabs-gcp-04-78814cacf3af-infra-source   --service-account=projects/qwiklabs-gcp-04-78814cacf3af/serviceAccounts/817174628708-compute@developer.gserviceaccount.com   --input-values="project=qwiklabs-gcp-04-78814cacf3af,network_prefix=cepf-infra-lb,group1_region=us-east1"
cd ~/cepf-iac 2>/dev/null || cd cepf-iac 2>/dev/null || true
python3 - << 'EOF'
import pathlib, re

# 1. Limpiar duplicado de load_balancing_scheme en main.tf
p_main = pathlib.Path("main.tf")
new_main, seen_lbs = [], False
for line in p_main.read_text().splitlines():
    if re.match(r'^\s*load_balancing_scheme\s*=', line):
        if not seen_lbs:
            indent = re.match(r'^(\s*)', line).group(1)
            new_main.append(f'{indent}load_balancing_scheme = "EXTERNAL_MANAGED"')
            seen_lbs = True
    else:
        new_main.append(line)
p_main.write_text("\n".join(new_main) + "\n")

# 2. Limpiar duplicados de database_version y target_size en mig.tf
p_mig = pathlib.Path("mig.tf")
new_mig, seen_db, seen_ts = [], False, False
for line in p_mig.read_text().splitlines():
    if re.match(r'^\s*database_version\s*=', line):
        if not seen_db:
            indent = re.match(r'^(\s*)', line).group(1)
            new_mig.append(f'{indent}database_version = "POSTGRES_14"')
            seen_db = True
    elif re.match(r'^\s*target_size\s*=', line):
        if not seen_ts:
            indent = re.match(r'^(\s*)', line).group(1)
            new_mig.append(f'{indent}target_size = var.target_size')
            seen_ts = True
    else:
        new_mig.append(line)
p_mig.write_text("\n".join(new_mig) + "\n")

print("Archivos main.tf y mig.tf limpios sin duplicados!")
EOF

# 3. Volver a subir los archivos corregidos al bucket
gcloud storage cp *.tf start-up.sh gs://qwiklabs-gcp-04-78814cacf3af-infra-source/
# 4. Relanzar el despliegue en Infrastructure Manager
gcloud infra-manager deployments apply lab-deployment   --project=qwiklabs-gcp-04-78814cacf3af   --location=us-east1   --gcs-source=gs://qwiklabs-gcp-04-78814cacf3af-infra-source   --service-account=projects/qwiklabs-gcp-04-78814cacf3af/serviceAccounts/817174628708-compute@developer.gserviceaccount.com   --input-values="project=qwiklabs-gcp-04-78814cacf3af,network_prefix=cepf-infra-lb,group1_region=us-east1"
