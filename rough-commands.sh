kubectl delete applications --all -n argocd && kubectl delete applicationsets --all -n argocd

cd /Users/shivam.anand/personal/argocd-research && \
  kubectl apply -f clusters/kind-shivam-playgroung-1/argocd-app-of-apps.yaml && \
  kubectl apply -f clusters/kind-shivam-playground-2/argocd-app-of-apps.yaml && \
  kubectl apply -f clusters/kind-shivam-playgroung-1/the-boss-app/argocd-application.yaml




kubectl delete applications --all -n argocd && kubectl delete applicationsets --all -n argocd
cd /Users/shivam.anand/personal/argocd-research && \ 
kubectl apply -f clusters/kind-shivam-playgroung-1/argocd-app-of-apps.yaml