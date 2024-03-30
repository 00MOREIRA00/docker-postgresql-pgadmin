# Docker Compose: PostgreSQL & PgAdmin

Este repositório contém um exemplo simples de como usar Docker Compose para criar e executar contêineres Docker para um banco de dados PostgreSQL e uma interface de administração PgAdmin.

## Pré-requisitos

Certifique-se de ter o Docker e o Docker Compose instalados em sua máquina.

* Docker
* Docker-Compose

## Uso

1. Clone este repositório em sua máquina local:

```
git clone https://github.com/seu-usuario/repo-docker-postgres-pgadmin.git
```

2. Navegue até o diretório do projeto:
```
cd repo-docker-postgres-pgadmin
```

3. Execute o seguinte comando para iniciar os contêineres:
```
docker-compose up -d
```
Isso iniciará os contêineres em segundo plano (-d).


4. Acesse PgAdmin em seu navegador:
    * URL: http://localhost:16543
        
       * Usuário: emailteste@gmail.com
       * Senha: testando123  

5. Dentro do PgAdmin, adicione um novo servidor PostgreSQL:

    * Nome do Servidor: Pode ser qualquer nome de sua preferência.
    * Host name/address: postgres
    * Porta: 5432
    * Usuário: postgres
    * Senha: testando123

6. Após adicionar o servidor, você poderá se conectar e começar a gerenciar seu banco de dados PostgreSQL.

7. Para parar os contêineres, execute:
```
docker-compose down
```

## Personalização

Você pode modificar as configurações do PostgreSQL no arquivo docker-compose.yml conforme necessário, como adicionar volumes, configurar senhas personalizadas etc.

## Avisos

* Não utilize essas configurações em um ambiente de produção sem adequada segurança e configuração.
As credenciais padrão são fornecidas apenas para fins de demonstração. 
* Certifique-se de alterá-las em um ambiente de produção.

## Contribuição

Contribuições são bem-vindas! Sinta-se à vontade para abrir problemas (issues) e enviar solicitações de pull (pull requests).





