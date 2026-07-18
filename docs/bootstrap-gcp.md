gcloud iam workload-identity-pools create "github-pool" `                                                               
>>   --project=$PROJECT_ID --location="global" --display-name="GitHub Actions Pool"

gcloud iam workload-identity-pools providers create-oidc "github-provider" `                                            
>>   --project=$PROJECT_ID --location="global" --workload-identity-pool="github-pool" `
>>   --display-name="GitHub Actions Provider" `                                              
>>   --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" `                                                            
>>   --attribute-condition="assertion.repository=='$GITHUB_REPO'" `
>>   --issuer-uri="https://token.actions.githubusercontent.com"

gcloud iam service-accounts create ci-deployer `                                                                        
>>   --project=$PROJECT_ID --display-name="CI/CD deployer for order-service"

gcloud iam service-accounts add-iam-policy-binding `                                                                    
>>   "ci-deployer@$PROJECT_ID.iam.gserviceaccount.com" `                               
>>   --project=$PROJECT_ID --role="roles/iam.workloadIdentityUser" `                         
>>   --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/$GITHUB_REPO"

foreach ($ROLE in @("roles/editor","roles/iam.serviceAccountAdmin","roles/resourcemanager.projectIamAdmin")) {          
>>   gcloud projects add-iam-policy-binding $PROJECT_ID `                              
>>     --member="serviceAccount:ci-deployer@$PROJECT_ID.iam.gserviceaccount.com" --role=$ROLE
>> }

gcloud iam workload-identity-pools providers describe "github-provider" `                                               
>>   --project=$PROJECT_ID --location="global" --workload-identity-pool="github-pool" `
>>   --format="value(name)"