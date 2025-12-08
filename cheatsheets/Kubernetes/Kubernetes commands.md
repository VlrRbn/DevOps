# Команды Kubernetes

---

## 0. Общий шаблон команд

```bash
kubectl [глобальные флаги] <command> <TYPE> [NAME] [flags]
```

Примеры:

```bash
kubectl get pods
kubectl describe pod my-pod
kubectl delete deployment backend
kubectl apply -f deployment.yaml

```

Полная помощь:

```bash
kubectl --help
kubectl <command> --help
kubectl api-resources          # все типы ресурсов
kubectl api-versions           # все версии API

```

---

## 1. Контексты и кластеры

```bash
kubectl config get-contexts          # список контекстов
kubectl config current-context       # текущий контекст
kubectl config use-context <name>    # переключиться

kubectl config set-context <name> \
  --cluster=<cluster> --user=<user> --namespace=<ns>

kubectl config delete-context <name>

kubectl cluster-info                 # инфа о кластере
kubectl cluster-info dump            # дамп всего для отладки

kubectl get nodes                    # все ноды
kubectl describe node <node-name>    # подробности ноды

```

---

## 2. Namespaces

```bash
kubectl get namespaces
kubectl get ns

kubectl create namespace dev
kubectl delete namespace dev

# использовать namespace на один вызов
kubectl get pods -n dev

# использовать namespace по умолчанию в контексте
kubectl config set-context --current --namespace=dev

```

---

## 3. Базовый CRUD по ресурсам

### get

```bash
kubectl get pods
kubectl get pods -o wide
kubectl get svc
kubectl get deployments
kubectl get all                      # pod, svc, deploy и т.п. в ns
kubectl get all -A                   # во всех ns (A = all-namespaces)
kubectl get pod my-pod -o yaml       # сырой YAML ресурса

```

### describe

```bash
kubectl describe pod my-pod
kubectl describe deployment my-deploy
kubectl describe svc my-service
kubectl describe node my-node

```

### create / apply / delete / edit

```bash
# создать из манифеста
kubectl apply -f app.yaml
kubectl apply -f k8s/                 # все файлы в каталоге

# создать "на лету"
kubectl create deployment nginx --image=nginx
kubectl create namespace stage

# удалить
kubectl delete -f app.yaml
kubectl delete pod my-pod
kubectl delete deployment my-deploy
kubectl delete pod,svc -l app=my-app  # по label selector

# редактировать прямо в кластере (через $EDITOR)
kubectl edit deployment my-deploy
kubectl edit configmap my-config

```

---

## 4. Логи, exec, port-forward — отладка

```bash
# логи пода
kubectl logs my-pod
kubectl logs my-pod -c sidecar           # конкретный контейнер
kubectl logs my-pod -f                   # follow (tail -f)
kubectl logs deployment/my-deploy        # все поды деплоя (новые версии kubectl)

# exec в контейнер
kubectl exec -it my-pod -- bash
kubectl exec -it my-pod -- sh
kubectl exec -it my-pod -c app -- bash

# port-forward (локальный порт -> под/сервис)
kubectl port-forward pod/my-pod 8080:80
kubectl port-forward svc/my-service 8080:80

```

---

## 5. Масштабирование и rollout

```bash
# масштабирование
kubectl scale deployment my-deploy --replicas=3

# autoscaler
kubectl autoscale deployment my-deploy --min=2 --max=5 --cpu-percent=80

# rollout
kubectl rollout status deployment my-deploy
kubectl rollout history deployment my-deploy
kubectl rollout history deployment my-deploy --revision=2
kubectl rollout undo deployment my-deploy
kubectl rollout undo deployment my-deploy --to-revision=2

```

---

## 6. Конфиг: ConfigMap и Secret

```bash
# ConfigMap из файла/директории
kubectl create configmap app-config --from-file=config.yaml
kubectl create configmap app-config --from-file=./config-dir/

# ConfigMap из литералов
kubectl create configmap app-config \
  --from-literal=ENV=prod \
  --from-literal=LOG_LEVEL=debug

# Secret из литералов
kubectl create secret generic app-secret \
  --from-literal=DB_USER=user \
  --from-literal=DB_PASSWORD=pass

# Secret из файла
kubectl create secret generic tls-secret \
  --from-file=cert.pem \
  --from-file=key.pem

# Просмотр
kubectl get configmaps
kubectl describe configmap app-config

kubectl get secrets
kubectl describe secret app-secret

# Содержимое secret в "человеческом" виде
kubectl get secret app-secret -o jsonpath='{.data}' | base64 --decode
# (делаешь jsonpath по конкретному ключу)

```

---

## 7. Deployment / Pod / Service / Ingress

```bash
# список
kubectl get deployments
kubectl get pods
kubectl get svc
kubectl get ingress
kubectl get ingress -A

# создать "быстрый" Deployment + Service
kubectl create deployment web --image=nginx
kubectl expose deployment web --type=ClusterIP --port=80
kubectl expose deployment web --type=LoadBalancer --port=80

# удалить
kubectl delete deployment web
kubectl delete svc web
kubectl delete ingress web-ingress

```

---

## 8. Job / CronJob

```bash
kubectl get jobs
kubectl describe job my-job
kubectl delete job my-job

kubectl get cronjobs
kubectl describe cronjob my-cron
kubectl delete cronjob my-cron

# создать job из изображения
kubectl create job pi --image=perl -- perl -Mbignum=bpi -wle 'print bpi(2000)'

```

---

## 9. Storage: PV / PVC / StorageClass

```bash
kubectl get pv
kubectl get pvc
kubectl get storageclass

kubectl describe pvc my-pvc
kubectl describe pv my-pv

kubectl delete pvc my-pvc
kubectl delete pv my-pv

```

---

## 10. RBAC и аккаунты

```bash
kubectl get serviceaccounts -A
kubectl describe serviceaccount default -n dev

kubectl get roles -A
kubectl get rolebindings -A
kubectl get clusterroles
kubectl get clusterrolebindings

kubectl describe role my-role -n dev
kubectl describe clusterrole my-cluster-role

```

---

## 11. Метрики, события, состояние кластера

```bash
# если установлен metrics-server
kubectl top nodes
kubectl top pods
kubectl top pods -A

# события
kubectl get events
kubectl get events -A
kubectl get events --sort-by='.lastTimestamp'

# состояние нод
kubectl get nodes
kubectl describe node my-node

```

---

## 12. Label, annotations, селекторы

```bash
# добавить/изменить label
kubectl label pod my-pod env=prod
kubectl label deployment my-deploy app=my-app --overwrite

# удалить label
kubectl label pod my-pod env-

# annotations
kubectl annotate pod my-pod description="Test pod"
kubectl annotate pod my-pod description-   # удалить

# выборка по label
kubectl get pods -l app=my-app
kubectl get pods -l 'env in (dev,stage)'

```

---

## 13. Node management: cordon, drain, taint

```bash
# запретить планирование новых подов на ноду
kubectl cordon my-node

# разрешить снова
kubectl uncordon my-node

# вычистить поды (для обслуживания)
kubectl drain my-node --ignore-daemonsets --delete-emptydir-data

# taints
kubectl taint nodes my-node key=value:NoSchedule
kubectl taint nodes my-node key:NoSchedule-    # убрать taint

```

---

## 14. Полезные флаги и трюки

```bash
# "показать, что будет сделано, но не применять"
kubectl apply -f app.yaml --dry-run=client

# сохранить YAML в файл
kubectl get deployment my-deploy -o yaml > my-deploy.yaml

# удобно вытащить одно поле
kubectl get pod my-pod -o jsonpath='{.status.podIP}'
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

# смотреть ресурсы во всех ns
kubectl get pods -A
kubectl get svc -A
kubectl get deployments -A

```

---

## 15. Как увидеть вообще ВСЕ ресурсы, которые есть в кластере

```bash
# все типы ресурсов и их сокращения
kubectl api-resources

# все ресурсы всех типов
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get -A --ignore-not-found

```

---

## 16. Главные команды, которые стоит отработать до автоматизма

```bash
kubectl get pods,svc,deploy -A
kubectl describe pod <name>
kubectl logs <pod> [-c <container>] -f
kubectl exec -it <pod> -- sh
kubectl apply -f <manifest>.yaml
kubectl delete -f <manifest>.yaml
kubectl rollout status deployment/<name>
kubectl scale deployment/<name> --replicas=N
kubectl top pods
kubectl get events --sort-by='.lastTimestamp'
kubectl config get-contexts
kubectl config use-context <ctx>

```

---