# kind - что пригодится в практике

---

## 1. Выбор версии Kubernetes

По умолчанию kind ставит не самую старую, но и не обязательно последнюю версию Kubernetes.

Можно прямо указать, какую версию нужно поставить:

```bash
kind create cluster --name dev --image kindest/node:v1.30.0

```

Где `kindest/node:v1.30.0` — это Docker-образ ноды с нужной версией k8s.

Это удобно, когда:

- в проде, например, `1.27`, и хочется локально тестить то же самое;
- нужно проверить, как манифесты ведут себя на разных версиях.

---

## 2. Полезные конфиги кластера (порт, ingress, volume и т.д.)

### Проброс портов с хоста в кластер

Например, чтобы Ingress/Service был доступен снаружи на 80/443:

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP

```

Запуск:

```bash
kind create cluster --name dev --config kind-config.yaml

```

Теперь то, что слушает 80/443 внутри кластера (через ingress), будет доступно и с машины.

---

### extraMounts — монтируем локальные файлы/директории в ноду

Можно подмонтировать директорию с хоста в ноду:

```yaml
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: /home/user/data
        containerPath: /data

```

Это полезно:

- для локальных сертификатов;
- для каких-то конфигов;
- для отладки storage-контейнеров.

---

## 3. Работа с Docker-образами (без пуша в registry)

kind: кластер использует Docker на той же машине.

Значит, можно:

1. Собрать образ локально:
    
    ```bash
    docker build -t myapp:dev .
    
    ```
    
2. Загрузить его в кластер:
    
    ```bash
    kind load docker-image myapp:dev --name dev
    
    ```
    
3. Использовать образ в манифесте:
    
    ```yaml
    containers:
      - name: myapp
        image: myapp:dev
    
    ```
    

Без Docker Hub, без приватных репозиториев — чисто локальная разработка.

---

## 4. Локальный Docker Registry + kind

Чуть более продвинуто: запускаешь локальный registry и подключаешь его к kind.

### Шаг 1: поднять registry

```bash
docker run -d -p 5001:5000 --name registry registry:2

```

### Шаг 2: конфиг kind’а с локальным registry

```yaml
# kind-registry-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
      endpoint = ["http://registry:5000"]
nodes:
  - role: control-plane
  - role: worker

```

Смысл простой: пушишь образы в `localhost:5001`, а kind их оттуда тянет.

---

## 5. Ingress-контроллер в kind

По умолчанию **ingress в кластере нет**.

Обычно ставят nginx-ingress:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

```

И вместе с пробросом портов (80/443) можно локально гонять ingress как в реальном кластере.

---

## 6. Использование kind в CI

Пример для GitHub Actions: прогнать тесты внутри kind-кластера.

```yaml
name: CI

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install kind
        run: |
          curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
          chmod +x ./kind
          sudo mv ./kind /usr/local/bin/kind

      - name: Create cluster
        run: kind create cluster --name ci

      - name: Deploy app
        run: |
          kubectl apply -f k8s/

      - name: Run tests
        run: |
          # тут e2e тесты
          kubectl get pods -A

```

Смысл: каждый pipeline поднимает чистый кластер, гоняет тесты, потом CI-среда сама его удаляет.

---

## 7. Отладка и логирование

Когда что-то идёт не так — пара полезных команд:

- Посмотреть контейнеры kind:
    
    ```bash
    docker ps | grep kind
    
    ```
    
- Логи ноды (control-plane):
    
    ```bash
    docker logs kind-control-plane
    
    ```
    
- Выгрузить все логи кластера:
    
    ```bash
    kind export logs ./kind-logs
    
    ```
    

---

## 8. Ограничения kind

kind — это **инструмент для разработки и тестов**, не прод:

- **Storage**:
    - Обычно всё хранится в контейнере.
    - Перезапустишь кластер — всё пропадёт.
- **LoadBalancer**:
    - Нет реального облачного LoadBalancer.
    - Используют NodePort + ingress.
- **Производительность**:
    - Это Docker-контейнеры, а не реальные VM на отдельном железе.
    - Для тяжёлых нагрузочных тестов лучше использовать «настоящий» кластер.

---

## 9. Мини-шпаргалка по командам kind

```bash
# Создать кластер (дефолтный)
kind create cluster

# Создать кластер с именем
kind create cluster --name dev

# Создать кластер с конфигом
kind create cluster --name dev --config kind-config.yaml

# Список кластеров
kind get clusters

# Удалить кластер
kind delete cluster --name dev

# Загрузить локальный Docker-образ в кластер
kind load docker-image myapp:dev --name dev

# Экспорт логов
kind export logs ./logs
```