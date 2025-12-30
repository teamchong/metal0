"""Example LogicTable: Fraud Detection

This demonstrates how to create a LogicTable that combines
data from multiple Lance tables with Python-defined scoring logic.

Usage:
    # As a module
    from fraud_detector import FraudDetector

    results = (
        FraudDetector
        .filter(lambda t: t.risk_score() > 0.7)
        .select('order_id', 'amount', (lambda t: t.risk_score(), 'risk'))
        .order_by(lambda t: t.risk_score(), desc=True)
        .limit(100)
        .to_arrow()
    )

SQL equivalent:
    WITH DATA (
        orders = 'orders.lance',
        customers = 'customers.lance'
    )
    FROM logic_table('fraud_detector.py') AS t
    WHERE t.risk_score() > 0.7
    ORDER BY t.risk_score() DESC
    LIMIT 100
"""

from lanceql import logic_table, Table


@logic_table
class FraudDetector:
    """Fraud detection logic combining order and customer data."""

    # Data sources - query engine handles loading
    orders = Table('orders.lance', hot_tier='2GB')
    customers = Table('customers.lance', hot_tier='1GB')

    # Risk weights
    HIGH_AMOUNT_THRESHOLD = 10000
    NEW_CUSTOMER_DAYS = 30
    HIGH_VELOCITY_THRESHOLD = 5

    def amount_score(self) -> float:
        """Score based on order amount."""
        amount = self.orders.amount
        if amount > self.HIGH_AMOUNT_THRESHOLD:
            return min(1.0, amount / 50000)
        return 0.0

    def customer_score(self) -> float:
        """Score based on customer risk factors."""
        score = 0.0

        # New customer penalty
        if hasattr(self.customers, 'days_since_signup'):
            if self.customers.days_since_signup < self.NEW_CUSTOMER_DAYS:
                score += 0.3

        # Previous fraud flag
        if hasattr(self.customers, 'previous_fraud'):
            if self.customers.previous_fraud:
                score += 0.5

        # Account verification
        if hasattr(self.customers, 'verified'):
            if not self.customers.verified:
                score += 0.2

        return min(1.0, score)

    def velocity_score(self) -> float:
        """Score based on order velocity."""
        if hasattr(self.customers, 'orders_last_hour'):
            velocity = self.customers.orders_last_hour
            if velocity > self.HIGH_VELOCITY_THRESHOLD:
                return min(1.0, velocity / 20)
        return 0.0

    def risk_score(self) -> float:
        """Combined risk score (0-1)."""
        return (
            self.amount_score() * 0.4 +
            self.customer_score() * 0.4 +
            self.velocity_score() * 0.2
        )

    def risk_category(self) -> str:
        """Categorize risk level."""
        score = self.risk_score()
        if score > 0.8:
            return 'critical'
        if score > 0.6:
            return 'high'
        if score > 0.3:
            return 'medium'
        return 'low'

    def should_block(self) -> bool:
        """Whether to block this transaction."""
        return self.risk_score() > 0.8

    def should_review(self) -> bool:
        """Whether to flag for manual review."""
        score = self.risk_score()
        return 0.5 < score <= 0.8


# For loading via LogicTable.load('fraud_detector.py')
Logic = FraudDetector


if __name__ == '__main__':
    # Demo usage
    print("Fraud Detector LogicTable")
    print("=" * 40)
    print()
    print("Usage:")
    print("  from fraud_detector import FraudDetector")
    print()
    print("  results = (")
    print("      FraudDetector")
    print("      .filter(lambda t: t.risk_score() > 0.7)")
    print("      .order_by(lambda t: t.risk_score(), desc=True)")
    print("      .limit(100)")
    print("      .to_arrow()")
    print("  )")
    print()
    print("Query plan:")
    from lanceql import LogicTableQuery
    query = LogicTableQuery(FraudDetector)
    print(query.filter(lambda t: t.risk_score() > 0.7).limit(100).explain())
