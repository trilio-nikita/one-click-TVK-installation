call_s3cfg_minio() {
  access_key=$1
  secret_key=$2
  host_base=$3
  host_bucket=$4
  bucket_location=$5
  use_https=$6
  cat >s3cfg_config <<-EOM
[default]
access_key = ${access_key}
access_token =
add_encoding_exts =
add_headers =
bucket_location = ${bucket_location}
cache_file =
cloudfront_host = cloudfront.amazonaws.com
default_mime_type = binary/octet-stream
delay_updates = False
delete_after = False
delete_after_fetch = False
delete_removed = False
dry_run = False
enable_multipart = True
encoding = UTF-8
encrypt = False
expiry_date =
expiry_days =
expiry_prefix =
follow_symlinks = False
force = False
get_continue = False
gpg_command = /usr/bin/gpg
gpg_decrypt = %(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_encrypt = %(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase =
guess_mime_type = True
host_base = ${host_base}
host_bucket = ${host_bucket}
human_readable_sizes = False
ignore_failed_copy = False
invalidate_default_index_on_cf = False
invalidate_default_index_root_on_cf = True
invalidate_on_cf = False
list_md5 = False
log_target_prefix =
max_delete = -1
mime_type =
multipart_chunk_size_mb = 15
preserve_attrs = True
progress_meter = True
proxy_host =
proxy_port = 0
put_continue = False
recursive = False
recv_chunk = 4096
reduced_redundancy = False
restore_days = 1
secret_key = ${secret_key}
send_chunk = 4096
server_side_encryption = False
simpledb_host = sdb.amazonaws.com
skip_existing = False
socket_timeout = 300
urlencoding_mode = normal
use_https = ${use_https}
use_mime_magic = True
verbosity = WARNING
website_error =
website_index = index.html
signature_v2 = False
EOM
}

ACCESS_KEY="GOOG2XWZQ3OXO254KGHWY3HD"
SECRET_KEY="AmvjksC9O8wLfcZNGavYlqmiJ6tUCzno7SHYqiXD"
URL="https://storage.googleapis.com"
bucket_name="tvk-target-oneclick"
region="us-east1"
call_s3cfg_minio "$ACCESS_KEY" "$SECRET_KEY" "$URL" "$URL" "us-east1" "true"
#create bucket
s3cmd --config s3cfg_config mb s3://"$bucket_name" 
ret_mgs=$?
echo $ret_mgs
