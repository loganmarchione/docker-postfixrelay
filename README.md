# docker-postfixrelay

[![Build Status](https://travis-ci.org/loganmarchione/docker-postfixrelay.svg?branch=master)](https://travis-ci.org/loganmarchione/docker-postfixrelay)

Runs Postfix (as a relay) in Docker
  - Source code: [GitHub](https://github.com/loganmarchione/docker-postfixrelay)
  - Docker container: [Docker Hub](https://hub.docker.com/r/loganmarchione/docker-postfixrelay)
  - Image base: [Alpine Linux](https://hub.docker.com/_/alpine/)
  - Init system: [dumb-init](https://github.com/Yelp/dumb-init)
  - Application: [Postfix](http://www.postfix.org/)


## Explanation
  - Most home ISPs block port 25, so outbound emails must be relayed through an external SMTP server (e.g., Gmail)
  - This container acts as a single collections point for devices needing to send email
  - ⚠️ Postfix acts as an open relay. As such, this is not meant to be run on the internet, only on a trusted internal network! ⚠️

```
        Internal (LAN) network                                        Public internet

------------------
|                |
| Device sending |                            |   |
| email alert    | -------------              |   |
|                |             |              |   |
------------------             |              |   |
                               |              | F |
------------------             v              | i |
|                |       ------------------   | r |    -----------------------------       -------------------
| Device sending |       |                |   | e |    |                           |       |                 |
| email alert    | ----> | This container | --| w |--> | SMTP server (e.g., Gmail) | ----> | Recipient email |
|                |       |                |   | a |    |                           |       |                 |
------------------       ------------------   | l |    -----------------------------       -------------------
                               ^              | l |
------------------             |              |   |
|                |             |              |   |
| Device sending |             |              |   |
| email alert    | -------------              |   |
|                |
------------------
```

## Docker image information

### Docker image tags
  - `latest`: Latest version
  - `X.X.X`: [Semantic version](https://semver.org/) (use if you want to stick on a specific version)

### Environment variables
| Variable    | Required? | Definition                       | Example                    | Comments                                                     |
|-------------|-----------|----------------------------------|----------------------------|--------------------------------------------------------------|
| TZ          | Yes       | Timezone                         | America/New_York           | https://en.wikipedia.org/wiki/List_of_tz_database_time_zones |
| RELAY_HOST  | Yes       | Public SMTP server to use        | smtp.gmail.com             |                                                              |
| RELAY_PORT  | Yes       | Public SMTP port to use          | 587                        |                                                              |
| RELAY_USER  | No        | Address to login to $RELAY_HOST  | SMTP username              |                                                              |
| RELAY_PASS  | No        | Password to login to $RELAY_HOST | SMTP password              | If using Gmail 2FA, you will need to setup an app password   |
| TEST_EMAIL  | No        | Address to receive test email    | receive_address@domain.com | If not set, test email will **not** be sent                  |

### Ports
| Port on host              | Port in container | Comments            |
|---------------------------|-------------------|---------------------|
| Choose at your discretion | 25                | Postfix SMTP server |

### Volumes
| Volume on host            | Volume in container | Comments                           |
|---------------------------|---------------------|------------------------------------|
| Choose at your discretion | /var/spool/postfix  | Used to store Postfix's mail spool |

### Example usage
Below is an example docker-compose.yml file.
```
version: '3'
services:
  postfixrelay:
    container_name: postfixrelay
    restart: unless-stopped
    environment:
      - TZ=America/New_York
      - RELAY_HOST=smtp.gmail.com
      - RELAY_PORT=587
      - RELAY_USER=your_email_here@gmail.com
      - RELAY_PASS=your_app_password_here
      - TEST_EMAIL=test_email@domain.com
    env_file:
      - /custom/files/postfixrelay.env
    networks:
      - postfixrelay
    ports:
      - '25:25'
    volumes:
      - 'postfixrelay_data:/var/spool/postfix'
    image: registry.internal.loganmarchione.xyz/loganmarchione/docker-postfixrelay:1.0

networks:
  postfixrelay:

volumes:
  postfixrelay_data:
    driver: local
```

## TODO
- [x] Add a [healthcheck](https://docs.docker.com/engine/reference/builder/#healthcheck)
- [ ] Add TLS support for SMTPD and listen on 587


