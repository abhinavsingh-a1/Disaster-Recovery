# ---------------------------------------------------------------------------
# HTTPS: one ACM certificate per region (an ALB can only use a certificate
# from its own region), validated through the hosted zone.
# Only created when hosted_zone_id is set.
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "primary" {
  count             = local.create_dns ? 1 : 0
  provider          = aws.primary
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "dr" {
  count             = local.create_dns && local.deploy_dr ? 1 : 0
  provider          = aws.dr
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM uses the same validation CNAME for the same domain in every region,
# so one record validates both certificates.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in flatten(aws_acm_certificate.primary[*].domain_validation_options) : o.domain_name => o
  }

  provider        = aws.primary
  zone_id         = var.hosted_zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "primary" {
  count                   = local.create_dns ? 1 : 0
  provider                = aws.primary
  certificate_arn         = aws_acm_certificate.primary[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_acm_certificate_validation" "dr" {
  count                   = local.create_dns && local.deploy_dr ? 1 : 0
  provider                = aws.dr
  certificate_arn         = aws_acm_certificate.dr[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
