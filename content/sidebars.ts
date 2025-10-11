import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  tkeSidebar: [
    'README',
    {
      type: 'category',
      label: '网络指南',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/networking'
      },
      items: [
        {
          type: 'category',
          label: '在 TKE 自建 Cilium',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/networking/cilium'
          },
          items: [
            'networking/cilium/install',
            {
              type: 'category',
              label: '附录',
              collapsed: true,
              link: {
                type: 'generated-index',
                slug: '/networking/cilium/appendix'
              },
              items: [
                {
                  type: 'category',
                  label: 'e2e 测试',
                  collapsed: true,
                  link: {
                    type: 'generated-index',
                    slug: '/networking/cilium/appendix/e2e'
                  },
                  items: [
                    'networking/cilium/appendix/e2e/iptables-tencentos44'
                  ]
                }
              ]
            }
          ],
        },
        {
          type: 'category',
          label: '在 TKE 自建 Nginx Ingress Controller',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/networking/ingress-nginx'
          },
          items: [
            'networking/ingress-nginx/quick-start',
            'networking/ingress-nginx/clb',
            'networking/ingress-nginx/clb-direct-access',
            'networking/ingress-nginx/high-concurrency',
            'networking/ingress-nginx/high-availability',
            'networking/ingress-nginx/observability',
            'networking/ingress-nginx/waf',
            'networking/ingress-nginx/multi-ingress-controller',
            'networking/ingress-nginx/billing',
            'networking/ingress-nginx/migrate',
            'networking/ingress-nginx/values-demo',
          ],
        },
        'networking/envoygateway',
        'networking/traefik',
        'networking/traffic-lossless-upgrade',
        'networking/clb-to-pod-directly',
        'networking/pod-eip',
        'networking/migrate-tcm-to-istio',
        'networking/ipv6',
        'networking/tke-extend-network-controller',
        'networking/sign-free-certs-for-dnspod',
      ],
    },
    {
      type: 'category',
      label: '存储指南',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/storage'
      },
      items: [
        'storage/cbs-pvc-expansion',
        'storage/readonlymany-pv',
        'storage/mount-cfs-with-v3',
      ],
    },
    {
      type: 'category',
      label: '弹性伸缩',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/autoscaling'
      },
      items: [
        {
          type: 'category',
          label: '事件驱动弹性伸缩最佳实践(KEDA)',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/autoscaling/keda'
          },
          items: [
            'autoscaling/keda/overview',
            'autoscaling/keda/install',
            'autoscaling/keda/cron',
            'autoscaling/keda/workload',
            'autoscaling/keda/prometheus',
            'autoscaling/keda/clb',
            'autoscaling/keda/pulsar',
            'autoscaling/keda/cnapigw',
          ]
        },
        'autoscaling/tke-autoscaling-placeholder',
      ],
    },
    {
      type: 'category',
      label: 'OPA 策略管理',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/opa'
      },
      items: [
        'opa/install',
        'opa/block-public-ingress',
      ],
    },
    {
      type: 'category',
      label: '监控指南',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/monitoring'
      },
      items: [
        'monitoring/prometheus-scrape-config',
        'monitoring/grafana',
        'monitoring/kube-prometheus-stack',
        'monitoring/event-alert',
      ],
    },
    {
      type: 'category',
      label: '镜像与仓库',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/images'
      },
      items: [
        'images/use-mirror-in-container',
        'images/use-foreign-container-image',
      ],
    },
    {
      type: 'category',
      label: '故障排查',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/troubleshooting'
      },
      items: [
        'troubleshooting/public-service-or-ingress-connect-failed',
      ],
    },
    {
      type: 'category',
      label: '应用管理',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/apps'
      },
      items: [
        'apps/upgrade-inplace'
      ]
    },
    {
      type: 'category',
      label: 'AI',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/ai'
      },
      items: [
        'ai/sglang-deepseek-r1',
        'ai/llm',
        'ai/faq',
      ],
    },
    {
      type: 'category',
      label: '游戏方案',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/game'
      },
      items: [
        'game/room-networking',
        'game/clb-pod-mapping',
        {
          type: 'category',
          label: 'OpenKruiseGame',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/game/okg'
          },
          items: [
            'game/okg/install',
            'game/okg/serverless',
            {
              type: 'category',
              label: '实践案例',
              collapsed: true,
              link: {
                type: 'generated-index',
                slug: '/game/cases'
              },
              items: [
                {
                  type: 'category',
                  label: '使用 OpenKruiseGame 部署我的世界',
                  collapsed: true,
                  link: {
                    type: 'generated-index',
                    slug: '/game/okg/cases/minecraft'
                  },
                  items: [
                    'game/okg/cases/minecraft/deploy',
                    'game/okg/cases/minecraft/storage',
                    'game/okg/cases/minecraft/client',
                    'game/okg/cases/minecraft/customize-state',
                  ]
                }
              ]
            },
          ]
        },
        {
          type: 'category',
          label: 'Agones',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/game/agones'
          },
          items: [
            'game/agones/install',
            'game/agones/unreal',
            'game/agones/showcase',
          ]
        }
      ]
    },
    {
      type: 'category',
      label: '常见应用部署',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/deploy'
      },
      items: [
        'deploy/cert-manager',
        'deploy/harbor',
        'deploy/gitlab',
        'deploy/kubesphere',
      ],
    },
    {
      type: 'category',
      label: '常见问题',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/faq'
      },
      items: [
        'faq/modify-rp-filter-causing-exception',
        'faq/clb-loopback',
        'faq/controller-manager-and-scheduler-unhealthy',
      ],
    },
    {
      type: 'category',
      label: '常用 YAML',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/yaml'
      },
      items: [
        'yaml/service',
        'yaml/ingress',
        'yaml/workload',
        'yaml/scheduling',
        'yaml/networking',
      ],
    },
    {
      type: 'category',
      label: '附录',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/appendix'
      },
      items: [
        'appendix/kubectl',
        'appendix/ingress-error-code',
        'appendix/eks-note',
      ],
    },
  ]
};

export default sidebars;
