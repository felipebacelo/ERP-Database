USE ERP;

-- CRIANDO PROCEDURE PARA INTEGRAR MATERIAS DA NOTA FISCAL NO ESTOQUE
CREATE PROCEDURE PROC_INTEGR_NF_ESTOQUE (@COD_EMPRESA INT, @NUM_NF INT, @DATA_MOVTO DATE)
AS
	BEGIN
		SET NOCOUNT ON
		DECLARE @TIP_MOV VARCHAR(1),
				@COD_MAT VARCHAR(50),
				@LOTE VARCHAR(15),
				@QTD DECIMAL(10, 2),
				@ERRO_INTERNO INT,
				@TIP_NF CHAR(1),
				@COD_MAT_AUX INT,
				@QTD_LOTE DECIMAL(10,2),
				@QTD_ATEND DECIMAL(10,2),
				@SALDO DECIMAL(10,2),
				@SALDO_AUX DECIMAL(10,2),
				@TESTE CHAR(1),
				@MSG VARCHAR(40)

		SET @QTD_ATEND = 0
		SET @SALDO = 0
		
		BEGIN TRANSACTION
-- VERFICANDO SE EXISTE DOCUMENTO
			IF (SELECT COUNT(*)
				FROM NOTA_FISCAL
				WHERE COD_EMPRESA = @COD_EMPRESA
				AND NUM_NF = @NUM_NF ) = 0
					BEGIN
						SET @ERRO_INTERNO = 1;
					END
-- VERIFCANDO SE EXISTE DOCUMENTO E EST� INTEGRADO
			ELSE IF (SELECT TOP 1 A.NUM_NF
					 FROM NOTA_FISCAL A
					 WHERE COD_EMPRESA = @COD_EMPRESA
					 AND A.NUM_NF = @NUM_NF
					 AND A.INTEGRADA_SUP= 'S') = @NUM_NF
						BEGIN
							SET @ERRO_INTERNO = 2;
						END
-- VERIFICANDO SE A OPERA��O � DE ENTRADA PARA EXECUTAR ENTRADA EM ESTOQUE
			ELSE IF (SELECT COUNT(*)
					 FROM NOTA_FISCAL A
					 WHERE COD_EMPRESA = @COD_EMPRESA
					 AND A.NUM_NF = @NUM_NFAND A.TIP_NF = 'E'
					 AND A.INTEGRADA_SUP = 'N') = 1
						BEGIN
							PRINT 'OPERA��O DE ENTRADA'
							BEGIN TRY
								DECLARE INTEGRA_ESTOQUE CURSOR FOR
								SELECT A.TIP_NF, B.COD_MAT,
								CONCAT(DATEPART(DAYOFYEAR, GETDATE()), '-', A.NUM_NF) LOTE, B.QTD
								FROM NOTA_FISCAL A
									INNER JOIN NOTA_FISCAL_ITENS B
									ON A.COD_EMPRESA = B.COD_EMPRESA
									AND A.NUM_NF = B.NUM_NF
								WHERE A.COD_EMPRESA = @COD_EMPRESA
								AND A.NUM_NF = @NUM_NF
								AND A.INTEGRADA_SUP = 'N'

								OPEN INTEGRA_ESTOQUE
									FETCH NEXT FROM INTEGRA_ESTOQUE
									INTO @TIP_MOV, @COD_MAT, @LOTE, @QTD
									WHILE @@FETCH_STATUS = 0 OR @@ERROR <> 0
										BEGIN
-- EXECUTANDO PROCEDURE DE ESTOQUE COMO PAR�METROS DO CURSOR
											EXEC PROC_GERA_ESTOQUE
											@COD_EMPRESA, @TIP_MOV, @COD_MAT, @LOTE, @QTD, @DATA_MOVTO

											FETCH NEXT FROM INTEGRA_ESTOQUE
											INTO @TIP_MOV, @COD_MAT, @LOTE, @QTD
									END
								CLOSE INTEGRA_ESTOQUE
								DEALLOCATE INTEGRA_ESTOQUE
							END TRY
								BEGIN CATCH
									SET @ERRO_INTERNO = 3;
									PRINT ''
									PRINT 'ERRO OCORREU'
									PRINT 'MENSAGEM: ' + ERROR_MESSAGE()
									PRINT 'PROCEDURE: ' + ERROR_PROCEDURE()
										IF (SELECT CURSOR_STATUS('GLOBAL', 'INTEGRA_ESTOQUE')) = 1
											BEGIN
												CLOSE INTEGRA_ESTOQUE
												DEALLOCATE INTEGRA_ESTOQUE
											END
								END CATCH
					END
-- VERIFICANDO SE A OPERA��O � DE SA�DA PARA EXECUTAR SA�DA EM ESTOQUE
			ELSE IF (SELECT COUNT(*)
					 FROM NOTA_FISCAL A
					 WHERE COD_EMPRESA = @COD_EMPRESA
					 AND A.NUM_NF = @NUM_NF
					 AND A.TIP_NF = 'S'
					 AND A.INTEGRADA_SUP = 'N') = 1
						BEGIN
							PRINT 'OPERA��O DE SA�DA'
							BEGIN TRY
								DECLARE LE_NFE_VENDA CURSOR FOR
								SELECT A.NUM_NF, A.TIP_NF, B.COD_MAT, B.QTD
								FROM NOTA_FISCAL A
									INNER JOIN NOTA_FISCAL_ITENS B
									ON A.COD_EMPRESA = B.COD_EMPRESA
									AND A.NUM_NF = B.NUM_NF
								WHERE A.COD_EMPRESA = @COD_EMPRESA
								AND A.INTEGRADA_SUP = 'N'
								AND A.NUM_NF = @NUM_NF
								AND A.TIP_NF = 'S'
								ORDER BY B.COD_MAT
								
								OPEN LE_NFE_VENDA
									FETCH NEXT FROM LE_NFE_VENDA
									INTO @NUM_NF, @TIP_NF, @COD_MAT, @QTD
									WHILE @@FETCH_STATUS = 0
										BEGIN
											IF (SELECT ISNULL(QTD_SALDO, 0) QTD_SALDO
												FROM ESTOQUE
												WHERE COD_EMPRESA = @COD_EMPRESA
												AND COD_MAT = @COD_MAT) < @QTD
												OR
												(SELECT ISNULL(QTD_SALDO, 0) QTD_SALDO
												FROM ESTOQUE
												WHERE COD_EMPRESA = @COD_EMPRESA
												AND COD_MAT = @COD_MAT) IS NULL
													BEGIN
														SET @ERRO_INTERNO = 4
														PRINT 'PASSEI AQUI SALDO'
														GOTO ERRO4
													END
											ELSE
												BEGIN
													SELECT @NUM_NF NOTA, @TIP_NF TIP_NF, @COD_MAT COD_MAT, @QTD QTD
													DECLARE INTEGRA_NFE_VENDA CURSOR FOR
													SELECT C.COD_MAT, C.QTD_LOTE, C.LOTEFROM ESTOQUE_LOTE C
													WHERE COD_EMPRESA = @COD_EMPRESA
													AND C.COD_MAT = @COD_MATAND C.QTD_LOTE > 0
													ORDER BY C.COD_MAT, C.LOTE

													OPEN INTEGRA_NFE_VENDA
														FETCH NEXT FROM INTEGRA_NFE_VENDA
														INTO @COD_MAT, @QTD_LOTE, @LOTE
														SET @SALDO = @QTD;
														SET @SALDO_AUX = @SALDO
														WHILE @@FETCH_STATUS = 0
															BEGIN
																IF @COD_MAT_AUX <> @COD_MAT
																	BEGIN
																		SET @QTD_ATEND = 0
																		SET @SALDO = @QTD;
																	END
																IF @SALDO <= 0
																	BEGIN
																		SET @QTD_ATEND=0
																	END
																IF @SALDO_AUX >= @QTD_LOTE
																	BEGIN
																		SET @QTD_ATEND = @QTD_ATEND + @QTD_LOTE
																		SET @SALDO = @SALDO - @QTD
																		SET @SALDO_AUX = @SALDO_AUX - @QTD_LOTE
																		SET @TESTE = '1'
																	END
																ELSE IF @SALDO_AUX < @QTD_LOTE
																	BEGIN
																		SET @SALDO = @SALDO - (@QTD - @QTD_LOTE)
																		SET @QTD_ATEND = @QTD_ATEND + @SALDO_AUX
																		SET @SALDO_AUX = @SALDO_AUX - @QTD_ATEND
																		SET @TESTE = '2'
																	END
																IF @SALDO_AUX >= 0 AND @QTD_ATEND > 0
																	BEGIN
																		SELECT @NUM_NF NUM_NF, @TIP_NF TIP_NF,
																		@COD_MAT COD_MAT, @QTD QTD, @QTD_LOTE QTD_LOTE,
																		@LOTE LOTE, @QTD_ATEND QTD_ATEND, @SALDO_AUX SD_AUX, @TESTE TESTE
																		
																		EXEC PROC_GERA_ESTOQUE
																		@COD_EMPRESA, @TIP_NF, @COD_MAT, @LOTE, @QTD_ATEND, @DATA_MOVTO
																		SET @COD_MAT_AUX=@COD_MAT;
																	END
																	
																	FETCH NEXT FROM INTEGRA_NFE_VENDA
																	INTO @COD_MAT, @QTD_LOTE, @LOTE
																END
														CLOSE INTEGRA_NFE_VENDA
														DEALLOCATE INTEGRA_NFE_VENDA
												END
											FETCH NEXT FROM LE_NFE_VENDA
											INTO @NUM_NF, @TIP_NF, @COD_MAT, @QTD
										END
										CLOSE LE_NFE_VENDA
										DEALLOCATE LE_NFE_VENDA
								END TRY
									BEGIN CATCH
										SET @ERRO_INTERNO = 3;
										PRINT ''
										PRINT 'ERRO OCORREU'
										PRINT 'MENSAGEM: ' + ERROR_MESSAGE()
										PRINT 'PROCEDURE: ' + ERROR_PROCEDURE()
											IF (SELECT CURSOR_STATUS('GLOBAL', 'LE_NFE_VENDA')) = 1
												BEGIN
													CLOSE LE_NFE_VENDA
													DEALLOCATE LE_NFE_VENDA
												END
											IF (SELECT CURSOR_STATUS('GLOBAL', 'INTEGRA_NFE_VENDA')) = 1
												BEGIN
													CLOSE INTEGRA_NFE_VENDA
													DEALLOCATE INTEGRA_NFE_VENDA
												END
									END CATCH
								END

-- VALIDA��ES FINAIS
-- GOTO
		ERRO4:
			IF (SELECT CURSOR_STATUS('GLOBAL', 'LE_NFE_VENDA')) = 1
				BEGIN
					CLOSE LE_NFE_VENDA
					DEALLOCATE LE_NFE_VENDA
				END
			IF (SELECT CURSOR_STATUS('GLOBAL', 'INTEGRA_NFE_VENDA')) = 1
				BEGIN
					CLOSE INTEGRA_NFE_VENDA
					DEALLOCATE INTEGRA_NFE_VENDA
				END
	IF @@ERROR <> 0
		BEGIN
			ROLLBACK
			PRINT @@ERROR
			PRINT 'OPERA��O CANCELADA'
		END
	ELSE IF @ERRO_INTERNO = 1
		BEGIN
			ROLLBACK
			PRINT 'DOCUMENTO N�O EXISTE'
		END
	ELSE IF @ERRO_INTERNO = 2
		BEGIN
			ROLLBACK
			PRINT 'DOCUMENTO J� INTEGRADO'
		END
	ELSE IF @ERRO_INTERNO = 3
		BEGIN
			ROLLBACK
			PRINT 'ERRO NA PROCEDURE DE ESTOQUE'
		END
	ELSE IF @ERRO_INTERNO = 4
		BEGIN
			ROLLBACK
			PRINT 'SALDO INSUFICIENTE'
		END
	ELSE
		BEGIN
			UPDATE NOTA_FISCAL SET INTEGRADA_SUP = 'S'
			WHERE COD_EMPRESA = @COD_EMPRESA
			AND NUM_NF = @NUM_NF;
			COMMIT
			PRINT 'INTEGRA��O CONCLU�DA'
		END
END

-- EXECUTANDO PROCEDURE PROC_INTEGR_NF_ESTOQUE
EXECUTE PROC_INTEGR_NF_ESTOQUE 1, 1, '01-01-2020'; -- ENTRADA

EXECUTE PROC_INTEGR_NF_ESTOQUE 1, 2, '01-01-2020'; -- ENTRADA

EXECUTE PROC_INTEGR_NF_ESTOQUE 1, 3, '01-01-2020'; -- ENTRADA

EXECUTE PROC_INTEGR_NF_ESTOQUE 1, 4, '01-01-2020'; -- ENTRADA

EXECUTE PROC_INTEGR_NF_ESTOQUE 1, 5, '01-01-2020'; -- SA�DA