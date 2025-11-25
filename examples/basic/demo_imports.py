"""Demo: Multi-level imports working"""
import calculator

def run():
    sum_result = calculator.add(10, 5)
    product_result = calculator.multiply(4, 7)
    return sum_result + product_result

result = run()
