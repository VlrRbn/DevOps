# kind - Kubernetes IN Docker

Инструмент, который позволяет поднимать кластеры Kubernetes прямо внутри Docker-контейнеров на твоей машине.

Используется он в основном для **локальной разработки, тестов и экспериментов**, а **НЕ** для продакшена.

---

## Что такое kind:

**kind** — это CLI-утилита, которая:

- запускает **контейнеры Docker**, внутри которых крутятся компоненты Kubernetes (control plane, worker'ы);
- собирает из них **полноценный Kubernetes-кластер**;
- управляет жизненным циклом этих кластеров (создать, удалить, настроить).

---

## Зачем он нужен:

### 1. Быстрый локальный Kubernetes

С помощью kind можно:

- поднять **кластер за пару секунд**;
- создать **несколько кластеров сразу** (например, для тестов multi-cluster сценариев);
- **сломать всё** и просто удалить кластер одной командой, без cleanup’а.

Пример:

```bash
kind create cluster --name dev-cluster
kubectl get nodes
kind delete cluster --name dev-cluster

```

---

### 2. Тестирование манифестов и Helm-чартов

Допустим, что ты пишешь:

- Deployment/Service/Ingress манифесты;
- Helm-чарт;
- kustomize-конфигурации;

Проверить, что всё работает, можно в kind:

```bash
kind create cluster --name test-helm
helm install myapp ./chart
kubectl get pods

```

Так ты тестируешь инфраструктуру локально.

---

### 3. CI/CD: прогон e2e-тестов (end-to-end)

kind используют в **CI-пайплайнах**:

- В GitHub Actions / GitLab CI можно:
    - поднять kind-кластер,
    - задеплоить приложение,
    - прогнать e2e/интеграционные тесты,
    - удалить кластер.

Это удобно, потому что:

- не нужен отдельный «живой» Kubernetes для тестов;
- всё воспроизводимо: каждый pipeline начинает с чистого кластера.

---

### 4. Обучение и эксперименты

Можно тренироватся с :

- `kubectl`,
- RBAC,
- NetworkPolicy,
- Ingress-контроллерами,
- CSI-драйверами и т.п.;
- попробовать разные версии Kubernetes;
- посмотреть, как ведут себя разные контроллеры/операторы;

**сломал кластер → удалил → создал новый → продолжаешь**.

---

## Как это работает технически

- kind использует **Docker** как runtime.
- Каждый «узел» кластера — это **контейнер Docker** с образом, в котором:
    - kubelet,
    - kubeadm,
    - прочие компоненты Kubernetes.
- При `kind create cluster` он:
    1. Поднимает контейнер(ы) — control-plane и worker’ы.
    2. Настраивает их через `kubeadm`.
    3. Прокидывает kubeconfig, чтобы можно было использовать `kubectl`.

Также можно:

- задать **конфиг кластера** в YAML: CNI, порты, Ingress, версии;
- использовать кастомные Docker-образы для узлов.

Пример конфигурации:

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  
```

Запуск:

```bash
kind create cluster --name mycluster --config kind-config.yaml

```

---

## Чем kind отличается от minikube / k3d

Коротко:

- **kind**
    - Заточен под **тестирование Kubernetes и CI**.
    - Кластер = Docker-контейнеры.
- **minikube**
    - Больше ориентирован на **локальную разработку приложений**.
    - Поднимает VM или контейнер в зависимости от драйвера.
- **k3d**
    - Обертка над **k3s в Docker**.
    - Легковесный Kubernetes (k3s) внутри Docker — часто для edge/IoT, но и локально удобен.

---

## Минимальный практический старт

1. Установить kind (Linux/macOS):
    
    ```bash
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-$(uname)-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    
    ```
    
2. Проверить:
    
    ```bash
    kind --version
    
    ```
    
3. Создать кластер:
    
    ```bash
    kind create cluster --name dev
    
    ```
    
4. Проверить доступ:
    
    ```bash
    kubectl cluster-info
    kubectl get nodes
    
    ```
    
5. Удалить:
    
    ```bash
    kind delete cluster --name dev
    
    ```