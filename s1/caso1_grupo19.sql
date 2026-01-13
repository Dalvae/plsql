-- caso 1: calculo pesos todosuma
-- grupo 19 - PRY2206

-- variables bind (parametros)
VARIABLE b_run_cliente VARCHAR2(20);
VARIABLE b_peso_normal NUMBER;
VARIABLE b_peso_extra_1 NUMBER;
VARIABLE b_peso_extra_2 NUMBER;
VARIABLE b_peso_extra_3 NUMBER;
VARIABLE b_tramo_1 NUMBER;
VARIABLE b_tramo_2 NUMBER;

-- aca se ponen los valores, cambiar el run para cada cliente
BEGIN
    :b_run_cliente := '212420034';  -- karen pradenas
    
    -- valores de pesos segun enunciado
    :b_peso_normal  := 1200;
    :b_peso_extra_1 := 100;   -- menor a 1 millon
    :b_peso_extra_2 := 300;   -- entre 1 y 3 millones
    :b_peso_extra_3 := 550;   -- mas de 3 millones
    
    -- tramos
    :b_tramo_1 := 1000000;
    :b_tramo_2 := 3000000;
END;
/

DECLARE
    -- variables para guardar datos del cliente
    v_nro_cliente       CLIENTE.NRO_CLIENTE%TYPE;
    v_nombre_completo   VARCHAR2(100);
    v_tipo_cliente      VARCHAR2(50);
    v_anio_anterior     NUMBER(4);
    
    -- variables para los calculos
    v_monto_total       NUMBER(12) := 0;
    v_bloques_100k      NUMBER(10) := 0;
    v_pesos_base        NUMBER(10) := 0;
    v_pesos_extra       NUMBER(10) := 0;
    v_total_pesos       NUMBER(10) := 0;

BEGIN
    -- sacamos el año anterior con extract (no usar fechas fijas)
    v_anio_anterior := EXTRACT(YEAR FROM SYSDATE) - 1;

    SELECT c.nro_cliente,
           c.pnombre || ' ' || c.appaterno,
           UPPER(tc.nombre_tipo_cliente)
      INTO v_nro_cliente,
           v_nombre_completo,
           v_tipo_cliente
      FROM CLIENTE c
      JOIN TIPO_CLIENTE tc ON c.cod_tipo_cliente = tc.cod_tipo_cliente
     WHERE c.numrun || c.dvrun = :b_run_cliente;

    -- sumamos todos los creditos del año anterior
    -- nvl por si no tiene creditos que no de error
    SELECT NVL(SUM(monto_solicitado), 0)
      INTO v_monto_total
      FROM CREDITO_CLIENTE
     WHERE nro_cliente = v_nro_cliente
       AND EXTRACT(YEAR FROM fecha_otorga_cred) = v_anio_anterior;

    v_bloques_100k := TRUNC(v_monto_total / 100000);
    
    -- pesos base = bloques * 1200
    v_pesos_base := v_bloques_100k * :b_peso_normal;
    
    -- pesos extra solo para independientes
    IF v_tipo_cliente LIKE '%INDEPENDIENTE%' THEN
        
        -- segun el tramo se calcula el extra
        IF v_monto_total < :b_tramo_1 THEN
            v_pesos_extra := v_bloques_100k * :b_peso_extra_1;
            
        ELSIF v_monto_total >= :b_tramo_1 AND v_monto_total <= :b_tramo_2 THEN
            v_pesos_extra := v_bloques_100k * :b_peso_extra_2;
            
        ELSIF v_monto_total > :b_tramo_2 THEN
            v_pesos_extra := v_bloques_100k * :b_peso_extra_3;
        END IF;
        
    ELSE
        v_pesos_extra := 0;
    END IF;
    
    v_total_pesos := v_pesos_base + v_pesos_extra;

    INSERT INTO CLIENTE_TODOSUMA (
        NRO_CLIENTE, RUN_CLIENTE, NOMBRE_CLIENTE, 
        TIPO_CLIENTE, MONTO_SOLIC_CREDITOS, MONTO_PESOS_TODOSUMA
    ) VALUES (
        v_nro_cliente, :b_run_cliente, v_nombre_completo,
        v_tipo_cliente, v_monto_total, v_total_pesos
    );

    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Cliente: ' || v_nombre_completo);
    DBMS_OUTPUT.PUT_LINE('Tipo: ' || v_tipo_cliente);
    DBMS_OUTPUT.PUT_LINE('Monto creditos: $' || v_monto_total);
    DBMS_OUTPUT.PUT_LINE('Total pesos: $' || v_total_pesos);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('error: no se encontro el cliente');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('error: ' || SQLERRM);
        ROLLBACK;
END;
/
