# kind commands

---

## 1. Управление кластерами

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `kind version` | Показывает версию kind | Проверить, что всё вообще установлено |
| `kind get clusters` | Список кластеров, созданных через kind | Увидеть все локальные кластера: `kind`, `lab27`, `playground` и т.п. |
| `kind create cluster` | Создаёт кластер `kind` по умолчанию | Самый простой кластер «из коробки» |
| `kind create cluster --name lab27` | Создаёт кластер с именем `lab27` | Удобно, когда у тебя несколько разных кластеров для разных лаб |
| `kind create cluster --name lab27 --config kind-config.yaml` | Создаёт кластер по кастомному конфигу | Маппинг портов, количество нод, ingress-контроллер и т.п. |
| `kind delete cluster` | Удаляет кластер `kind` по умолчанию | Быстро снести дефолтный кластер |
| `kind delete cluster --name lab27` | Удаляет кластер с именем `lab27` | Полностью убрать тестовый кластер, освободить ресурсы |

> После `kind create cluster --name lab27`  в `kubeconfig` появляется контекст `kind-lab27`.
> 

---

## 2. kubeconfig и контексты

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `kubectl config get-contexts` | Показывает все контексты kubectl | Увидеть `kind-lab27` и др. кластера |
| `kubectl config use-context kind-lab27` | Переключиться на кластер kind с именем `lab27` | Чтобы все `kubectl get pods` шли именно в твой kind-кластер |
| `kind export kubeconfig --name lab27` | Экспортирует kubeconfig для кластера | Если kubeconfig не обновился автоматически по какой-то причине |

Обычно достаточно:

```bash
kind create cluster --name lab27
kubectl config use-context kind-lab27
kubectl get nodes

```

---

## 3. Загрузка образов в kind

> Важный момент: ноды kind — это докер-контейнеры. Они не видят локальный Docker-демон «по воздуху».
> 
> 
> Поэтому образ, который есть локально, нужно явно «загрузить» в кластер. 
> 

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `kind load docker-image lab27-web:dev --name lab27` | Кладёт локальный Docker-образ в ноды кластера | Когда образ `lab27-web:dev` есть только локально, без registry |
| `kind load docker-image ghcr.io/you/lab27-web:dev --name lab27` | То же самое, но с образом из registry (ниже latency при pull) | Ускорить тесты, не ждать pull внутри кластера |
| `kind load image-archive lab27-web.tar --name lab27` | Загружает образ из tar-архива | Полезно в CI, если образ передаётся как файл, а не через registry |

Сценарий:

```bash
# Локально собрать образ
docker build -t lab27-web:dev .

# Загрузить его в kind-кластер
kind load docker-image lab27-web:dev --name lab27

# В манифестах k8s:
# image: lab27-web:dev

```

---

## 4. Логи и отладка кластера

| Команда | Что делает | Зачем / пример |
| --- | --- | --- |
| `kind export logs --name lab27` | Выгружает логи кластера в локальную папку `./logs` | Когда что-то сильно сломалось, а ты не понимаешь почему |
| `kind export logs --name lab27 --logdir ./kind-logs-lab27` | То же, но в указанную директорию | Удобно для архива/отправки логов, если нужно разбирать отдельно |

Чаще всего хватит `kubectl`:

```bash
kubectl get nodes
kubectl get pods -A
kubectl describe pod ...
kubectl logs ...

```

А `kind export logs` — уже когда хочется покопать системно (проблемы с control-plane, CNI и т.д.).

---

## 5. Подводные камни

**1. Docker не запущен**

- kind без Docker — мёртвый.
- Если команда `kind create cluster` падает странной ошибкой — сначала проверить: `docker ps`

---

**2. Образы не находятся**

Симптом:

- В подах статус `ImagePullBackOff`/`ErrImagePull`,
- Но локально `docker image ls` показывает этот образ.

Решение:

- Либо пушить в реальный registry и указывать `image: ghcr.io/...`,
- Либо:
    
    ```bash
    kind load docker-image lab27-web:dev --name lab27
    ```
    

---

**3. Порты снаружи не доступны** «поднял сервис в kind, но `curl http://127.0.0.1:8080` не работает»

Варианты:

1. `kubectl port-forward`:
    
    ```bash
    kubectl port-forward svc/lab27-web 8080:80 -n lab27
    ```
    
2. В `kind-config.yaml` описать `extraPortMappings` (маппинг портов ноды на localhost) и создать кластер с `--config`.

---

**4. Всё пропало после перезагрузки / удаления**

kind-кластер `Ephemeral` по своей сути:

- Удалил `kind delete cluster --name lab27` — весь кластер и его state ушли.

---

## 6. Быстрые блоки

### 6.1. Базовый сценарий для лабы

```bash
# 1. Создаём кластер
kind create cluster --name lab27

# 2. Переключаемся на него
kubectl config use-context kind-lab27

# 3. Проверяем
kubectl get nodes

# 4. Деплоим свои манифесты
kubectl apply -f labs/lesson_27/k8s/namespace.yaml
kubectl apply -f labs/lesson_27/k8s/

```

---

### 6.2. Кластер с кастомным конфигом

`kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 8080
        protocol: TCP

```

Команда:

```bash
kind create cluster --name lab27 --config kind-config.yaml
kubectl config use-context kind-lab27

```

Теперь сервис, который слушает `NodePort: 30080` внутри кластера, будет доступен на `localhost:8080`.